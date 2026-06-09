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

import React, { useState, useEffect, useRef } from 'react';
import axios from 'axios';
import { Terminal } from '@xterm/xterm';
import { FitAddon } from '@xterm/addon-fit';
import '@xterm/xterm/css/xterm.css';

const App: React.FC = () => {
  const [isLoggedIn, setIsLoggedIn] = useState(false);
  const [token, setToken] = useState('');
  const [loginName, setLoginName] = useState('');
  const [password, setPassword] = useState('');
  const [authMethod, setAuthMethod] = useState<'ldap' | 'password'>('ldap');
  const [targets, setTargets] = useState<any[]>([]);
  const [selectedTarget, setSelectedTarget] = useState<string>('');
  const [hosts, setHosts] = useState<any[]>([]);
  const [selectedHost, setSelectedHost] = useState<string>('');
  const [session, setSession] = useState<{ sessionId: string; authorizationToken: string; sshUser: string; sshPassword: string } | null>(null);
  const [status, setStatus] = useState<string>('Ready');
  const [error, setError] = useState<string | null>(null);
  const terminalRef = useRef<HTMLDivElement>(null);
  const xtermRef = useRef<Terminal | null>(null);
  const wsRef = useRef<WebSocket | null>(null);

  const ldapAuthMethodId = import.meta.env.VITE_LDAP_AUTH_METHOD_ID || '';

  useEffect(() => {
    if (isLoggedIn && token) {
      fetchTargets();
    }
  }, [isLoggedIn, token]);

  useEffect(() => {
    if (selectedTarget && token) {
      fetchHosts(selectedTarget);
    } else {
      setHosts([]);
      setSelectedHost('');
    }
  }, [selectedTarget, token]);

  const fetchHosts = async (targetId: string) => {
    try {
      setStatus('Discovering hosts...');
      setHosts([]);
      setSelectedHost('');
      // 1. Get target details to find host sets
      const targetResp = await axios.get(`/boundary/v1/targets/${targetId}`, {
        headers: { 'Authorization': `Bearer ${token}` }
      });
      const hostSetIds = targetResp.data.item.host_set_ids || [];
      
      // 2. Fetch hosts for each host set
      const allHosts: any[] = [];
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
    } catch (err: any) {
      console.error('Failed to fetch hosts:', err);
      // Don't set global error here to avoid blocking login flow, just log it
      setStatus('Target selected');
    }
  };

  const fetchTargets = async () => {
    setStatus('Discovering targets...');
    try {
      const resp = await axios.get('/boundary/v1/targets?recursive=true&scope_id=global', {
        headers: { 'Authorization': `Bearer ${token}` }
      });
      const discoveredTargets = resp.data.items || [];
      setTargets(discoveredTargets);
      setStatus('Targets discovered');
      
      // Always reset selection on fresh discovery to avoid stale IDs
      setSelectedTarget('');
    } catch (err: any) {
      console.error('Discovery: Failed!', err);
      setError(`Failed to discover targets: ${err.response?.data?.message || err.message}`);
      setStatus('Error');
    }
  };

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setStatus('Logging in...');
    setError(null);
    try {
      const payload: Record<string, string> = { login_name: loginName, password };
      if (authMethod === 'ldap' && ldapAuthMethodId) {
        payload.auth_method_id = ldapAuthMethodId;
      }
      const resp = await axios.post(`/auth/login`, payload);
      setToken(resp.data.token);
      setIsLoggedIn(true);
      setStatus('Logged in');
    } catch (err: any) {
      const msg = err.response?.data?.error || err.response?.data || err.message;
      setError(`Login failed: ${typeof msg === 'object' ? JSON.stringify(msg) : msg}`);
      setStatus('Error');
    }
  };

  const handleConnect = async () => {
    console.log('Connect attempt: Target =', selectedTarget, 'Host =', selectedHost);
    if (!selectedTarget || selectedTarget === '') {
      setError('Please select a target');
      return;
    }
    // If we have discovered hosts, one MUST be selected
    if (hosts.length > 0 && (!selectedHost || selectedHost === '')) {
      setError('Please select a specific host from the list');
      return;
    }
    
    setStatus('Authorizing session...');
    setError(null);
    try {
      // Authorize session DIRECTLY against Boundary
      const payload: any = {};
      if (selectedHost) {
        payload.host_id = selectedHost;
      }
      
      const resp = await axios.post(
        `/boundary/v1/targets/${selectedTarget}:authorize-session`,
        payload,
        { headers: { 'Authorization': `Bearer ${token}` } }
      );
      
      const sa = resp.data;
      console.log('Authorization successful:', sa);

      // Extract brokered credentials from Boundary's authorize-session response
      const credentials = sa.credentials || [];
      const sshCred = credentials.find((c: any) => c.credential?.username) || {};
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
    } catch (err: any) {
      const msg = err.response?.data || err.message;
      setError(`Authorization failed: ${typeof msg === 'object' ? JSON.stringify(msg) : msg}`);
      setStatus('Error');
    }
  };

  useEffect(() => {
    if (session && terminalRef.current) {
      setStatus('Connecting to WebSocket...');
      // Clean up previous instance if any
      if (xtermRef.current) {
        xtermRef.current.dispose();
        xtermRef.current = null;
      }
      if (wsRef.current) {
        wsRef.current.close();
      }

      const term = new Terminal({
        cursorBlink: true,
        fontFamily: 'monospace',
        theme: {
          background: '#000000',
        }
      });
      const fitAddon = new FitAddon();
      term.loadAddon(fitAddon);
      term.open(terminalRef.current);
      fitAddon.fit();

      const protocol = window.location.protocol === 'https:' ? 'wss://' : 'ws://';
      const ws = new WebSocket(`${protocol}${window.location.host}/ws/ssh`);
      wsRef.current = ws;
      ws.onopen = () => {
        console.log('WebSocket connected');
        setStatus('Negotiating SSH...');
        ws.send(JSON.stringify({
          token: session.authorizationToken,
          ssh_user: session.sshUser,
          ssh_password: session.sshPassword,
        }));
      };

      ws.onmessage = (event) => {
        const msg = JSON.parse(event.data);
        if (msg.type === 'data') {
          if (status !== 'Connected') setStatus('Connected');
          term.write(msg.data);
        }
      };

      ws.onerror = (e) => {
        console.error('WebSocket error:', e);
        setError('WebSocket connection failed');
        setStatus('Error');
      };

      ws.onclose = () => {
        console.log('WebSocket closed');
        if (status !== 'Error') setStatus('Disconnected');
      };

      term.onData((data) => {
        if (ws.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify({ type: 'data', data }));
        }
      });

      xtermRef.current = term;
      wsRef.current = ws;

      const handleResize = () => fitAddon.fit();
      window.addEventListener('resize', handleResize);

      return () => {
        window.removeEventListener('resize', handleResize);
        term.dispose();
        ws.close();
      };
    }
  }, [session]);

  if (!isLoggedIn) {
    return (
      <div className="flex items-center justify-center min-h-screen bg-gray-900 text-white">
        <form onSubmit={handleLogin} className="p-8 bg-gray-800 rounded-lg shadow-xl w-96">
          <h2 className="text-2xl font-bold mb-6 text-center">Comet Boundary Login</h2>
          {error && <div className="mb-4 p-2 bg-red-900 border border-red-700 text-red-100 text-sm rounded">{error}</div>}
          <div className="mb-4">
            <label className="block text-sm font-medium mb-1">Auth Method</label>
            <select
              className="w-full p-2 rounded bg-gray-700 border border-gray-600 focus:outline-none focus:ring-2 focus:ring-blue-500"
              value={authMethod}
              onChange={(e) => setAuthMethod(e.target.value as 'ldap' | 'password')}
            >
              <option value="ldap">LDAP</option>
              <option value="password">Password (Admin)</option>
            </select>
          </div>
          <div className="mb-4">
            <label className="block text-sm font-medium mb-1">Username</label>
            <input
              type="text"
              className="w-full p-2 rounded bg-gray-700 border border-gray-600 focus:outline-none focus:ring-2 focus:ring-blue-500"
              value={loginName}
              onChange={(e) => setLoginName(e.target.value)}
              placeholder={authMethod === 'ldap' ? 'e.g. alice' : 'e.g. admin'}
            />
          </div>
          <div className="mb-6">
            <label className="block text-sm font-medium mb-1">Password</label>
            <input
              type="password"
              className="w-full p-2 rounded bg-gray-700 border border-gray-600 focus:outline-none focus:ring-2 focus:ring-blue-500"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
            />
          </div>
          <button
            type="submit"
            disabled={status.includes('...')}
            className="w-full p-2 rounded bg-blue-600 hover:bg-blue-700 font-bold transition-colors disabled:opacity-50"
          >
            {status.includes('...') ? status : 'Login'}
          </button>
        </form>
      </div>
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
          <div className="flex items-center gap-4">
            <select
              className="p-2 rounded bg-gray-800 border border-gray-700 w-48 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
              value={selectedTarget}
              onChange={(e) => {
                console.log('Target selected:', e.target.value);
                setSelectedTarget(e.target.value);
              }}
              disabled={status === 'Connected' || status === 'Discovering targets...'}
            >
              <option value="">{status === 'Discovering targets...' ? 'Loading Targets...' : 'Select Target...'}</option>
              {targets.map((t) => (
                <option key={t.id} value={t.id}>
                  {t.name || t.id}
                </option>
              ))}
            </select>

            {status === 'Discovering hosts...' ? (
              <div className="text-xs text-blue-400 animate-pulse">Loading Hosts...</div>
            ) : (
              selectedTarget && hosts.length > 1 && (
                <select
                  className="p-2 rounded bg-gray-800 border border-gray-700 w-48 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
                  value={selectedHost}
                  onChange={(e) => {
                    console.log('Host selected:', e.target.value);
                    setSelectedHost(e.target.value);
                  }}
                  disabled={status === 'Connected'}
                >
                  <option value="">Select Host...</option>
                  {hosts.map((h) => (
                    <option key={h.id} value={h.id}>
                      {h.name || h.address || h.id}
                    </option>
                  ))}
                </select>
              )
            )}

            <button
              onClick={handleConnect}
              disabled={status === 'Connected' || status.includes('...') || (selectedTarget && status !== 'Hosts discovered' && status !== 'Target selected')}
              className="p-2 px-6 rounded bg-green-600 hover:bg-green-700 font-bold transition-colors text-sm disabled:opacity-50"
            >
              {status === 'Connected' ? 'Connected' : 'Connect'}
            </button>
          </div>
        </div>

        {error && <div className="mb-4 p-3 bg-red-900 border border-red-700 text-red-100 rounded text-sm">{error}</div>}
        
        {/* Debug info (hidden in production, but useful for now) */}
        {/* <div className="text-xs text-gray-500 mb-2">Target: {selectedTarget || 'none'} | Host: {selectedHost || 'none'} | Status: {status}</div> */}

        <div className="bg-black rounded-lg overflow-hidden border border-gray-800 shadow-2xl">
          <div
            ref={terminalRef}
            style={{ height: '600px', width: '100%' }}
            className="p-2"
          />
        </div>
      </div>
    </div>
  );
};

export default App;
