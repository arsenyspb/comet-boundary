/*
 * Copyright 2026 Arseny Chernov
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import React, { useState, useEffect } from 'react';
import axios from 'axios';
import LoginForm from './components/LoginForm';
import TargetSelector from './components/TargetSelector';
import type { BoundaryTarget, BoundaryHost } from './components/TargetSelector';
import TerminalView from './components/TerminalView';
import type { SSHSession } from './components/TerminalView';

const App: React.FC = () => {
  const [isLoggedIn, setIsLoggedIn] = useState(false);
  const [token, setToken] = useState('');
  const [targets, setTargets] = useState<BoundaryTarget[]>([]);
  const [selectedTarget, setSelectedTarget] = useState<string>('');
  const [hosts, setHosts] = useState<BoundaryHost[]>([]);
  const [selectedHost, setSelectedHost] = useState<string>('');
  const [session, setSession] = useState<SSHSession | null>(null);
  const [status, setStatus] = useState<string>('Ready');
  const [error, setError] = useState<string | null>(null);

  const ldapAuthMethodId = import.meta.env.VITE_LDAP_AUTH_METHOD_ID || '';

  useEffect(() => {
    const fetchTargets = async () => {
      setStatus('Discovering targets...');
      try {
        const resp = await axios.get('/boundary/v1/targets?recursive=true&scope_id=global', {
          headers: { 'Authorization': `Bearer ${token}` }
        });
        const discoveredTargets = resp.data.items || [];
        setTargets(discoveredTargets);
        setStatus('Targets discovered');
        setSelectedTarget('');
      } catch (err: unknown) {
        const axErr = err as { response?: { data?: { message?: string } }; message?: string };
        console.error('Discovery: Failed!', err);
        setError(`Failed to discover targets: ${axErr.response?.data?.message || axErr.message}`);
        setStatus('Error');
      }
    };

    if (isLoggedIn && token) {
      fetchTargets();
    }
  }, [isLoggedIn, token]);

  useEffect(() => {
    const fetchHosts = async (targetId: string) => {
      try {
        setStatus('Discovering hosts...');
        setHosts([]);
        setSelectedHost('');
        const targetResp = await axios.get(`/boundary/v1/targets/${targetId}`, {
          headers: { 'Authorization': `Bearer ${token}` }
        });
        const hostSetIds = targetResp.data.item.host_set_ids || [];

        const allHosts: BoundaryHost[] = [];
        for (const hostSetId of hostSetIds) {
          const hsResp = await axios.get(`/boundary/v1/host-sets/${hostSetId}?list_hosts=true`, {
            headers: { 'Authorization': `Bearer ${token}` }
          });
          if (hsResp.data.item.hosts) {
            allHosts.push(...hsResp.data.item.hosts);
          }
        }

        setHosts(allHosts);
        if (allHosts.length === 1) {
          setSelectedHost(allHosts[0].id);
        } else {
          setSelectedHost('');
        }
        setStatus('Hosts discovered');
      } catch (err: unknown) {
        console.error('Failed to fetch hosts:', err);
        setStatus('Target selected');
      }
    };

    if (selectedTarget && token) {
      fetchHosts(selectedTarget);
    }
  }, [selectedTarget, token]);

  const handleTargetChange = (t: string) => {
    setSelectedTarget(t);
    if (!t) {
      setHosts([]);
      setSelectedHost('');
    }
  };

  const handleLoginSuccess = (newToken: string) => {
    setToken(newToken);
    setIsLoggedIn(true);
  };

  const handleConnect = async () => {
    if (!selectedTarget || selectedTarget === '') {
      setError('Please select a target');
      return;
    }
    if (hosts.length > 0 && (!selectedHost || selectedHost === '')) {
      setError('Please select a specific host from the list');
      return;
    }

    setStatus('Authorizing session...');
    setError(null);
    try {
      const payload: Record<string, string> = {};
      if (selectedHost) {
        payload.host_id = selectedHost;
      }

      const resp = await axios.post(
        `/boundary/v1/targets/${selectedTarget}:authorize-session`,
        payload,
        { headers: { 'Authorization': `Bearer ${token}` } }
      );

      const sa = resp.data;
      const credentials = sa.credentials || [];
      const sshCred = credentials.find((c: { credential?: { username?: string } }) => c.credential?.username) || {};
      const sshUser = sshCred.credential?.username || '';
      const sshPassword = sshCred.credential?.password || '';

      if (!sshUser || !sshPassword) {
        setError('Credential brokering failed: no credentials returned by Boundary. Ensure a credential source is linked to the target.');
        setStatus('Error');
        return;
      }

      setSession({
        sessionId: sa.session_id,
        authorizationToken: sa.authorization_token,
        sshUser,
        sshPassword,
      });
      setStatus('Session authorized');
    } catch (err: unknown) {
      const axErr = err as { response?: { data?: unknown }; message?: string };
      const msg = axErr.response?.data || axErr.message;
      setError(`Authorization failed: ${typeof msg === 'object' ? JSON.stringify(msg) : msg}`);
      setStatus('Error');
    }
  };

  if (!isLoggedIn) {
    return (
      <LoginForm
        ldapAuthMethodId={ldapAuthMethodId}
        onLoginSuccess={handleLoginSuccess}
        status={status}
        setStatus={setStatus}
        error={error}
        setError={setError}
      />
    );
  }

  return (
    <div className="p-4 bg-gray-900 min-h-screen text-white font-sans">
      <div className="max-w-6xl mx-auto">
        <div className="flex items-center justify-between mb-8">
          <div>
            <h1 className="text-3xl font-bold">Comet Boundary</h1>
            <div className="flex items-center gap-2 mt-1">
              <span className={`w-2 h-2 rounded-full ${status === 'Connected' ? 'bg-green-500' : 'bg-yellow-500'}`}></span>
              <span className="text-xs text-gray-400 font-medium uppercase tracking-wider">{status}</span>
            </div>
          </div>
          <TargetSelector
            targets={targets}
            selectedTarget={selectedTarget}
            onTargetChange={handleTargetChange}
            hosts={hosts}
            selectedHost={selectedHost}
            onHostChange={setSelectedHost}
            status={status}
            onConnect={handleConnect}
          />
        </div>

        {error && <div className="mb-4 p-3 bg-red-900 border border-red-700 text-red-100 rounded text-sm">{error}</div>}

        {session ? (
          <TerminalView session={session} setStatus={setStatus} setError={setError} />
        ) : (
          <div className="bg-black rounded-lg overflow-hidden border border-gray-800 shadow-2xl">
            <div style={{ height: '600px', width: '100%' }} className="p-2" />
          </div>
        )}
      </div>
    </div>
  );
};

export default App;
