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

type AuthMode = 'password' | 'ldap';

const App: React.FC = () => {
  const [isLoggedIn, setIsLoggedIn] = useState(false);
  const [token, setToken] = useState('');
  const [authMode, setAuthMode] = useState<AuthMode>('ldap');
  const [loginName, setLoginName] = useState('');
  const [password, setPassword] = useState('');
  const [targetId, setTargetId] = useState(import.meta.env.VITE_TARGET_ID || '');
  const [session, setSession] = useState<{ sessionId: string; authorizationToken: string } | null>(null);
  const [status, setStatus] = useState<string>('Ready');
  const [error, setError] = useState<string | null>(null);
  const terminalRef = useRef<HTMLDivElement>(null);
  const xtermRef = useRef<Terminal | null>(null);
  const wsRef = useRef<WebSocket | null>(null);

  const ldapAuthMethodId = import.meta.env.VITE_LDAP_AUTH_METHOD_ID || '';

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setStatus('Logging in...');
    setError(null);
    try {
      const payload: Record<string, string> = { login_name: loginName, password };
      if (authMode === 'ldap' && ldapAuthMethodId) {
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
    setStatus('Authorizing session...');
    setError(null);
    try {
      const resp = await axios.post(
        `/sessions/authorize`,
        { target_id: targetId },
        { headers: { 'X-Boundary-Token': token } }
      );
      console.log('Authorization successful:', resp.data);
      setSession({
        sessionId: resp.data.session_id,
        authorizationToken: resp.data.authorization_token,
      });
      setStatus('Session authorized');
    } catch (err: any) {
      const msg = err.response?.data || err.message;
      setError(`Authorization failed: ${msg}`);
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
        ws.send(JSON.stringify({ token: session.authorizationToken }));
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
          <div className="flex mb-6 rounded overflow-hidden border border-gray-600">
            <button
              type="button"
              className={`flex-1 p-2 text-sm font-medium transition-colors ${authMode === 'ldap' ? 'bg-blue-600 text-white' : 'bg-gray-700 text-gray-300 hover:bg-gray-600'}`}
              onClick={() => setAuthMode('ldap')}
            >
              LDAP
            </button>
            <button
              type="button"
              className={`flex-1 p-2 text-sm font-medium transition-colors ${authMode === 'password' ? 'bg-blue-600 text-white' : 'bg-gray-700 text-gray-300 hover:bg-gray-600'}`}
              onClick={() => setAuthMode('password')}
            >
              Password
            </button>
          </div>
          <div className="mb-4">
            <label className="block text-sm font-medium mb-1">Username</label>
            <input
              type="text"
              className="w-full p-2 rounded bg-gray-700 border border-gray-600 focus:outline-none focus:ring-2 focus:ring-blue-500"
              value={loginName}
              onChange={(e) => setLoginName(e.target.value)}
              placeholder={authMode === 'ldap' ? 'LDAP username (e.g. alice)' : 'admin'}
            />
          </div>
          <div className="mb-6">
            <label className="block text-sm font-medium mb-1">Password</label>
            <input
              type="password"
              className="w-full p-2 rounded bg-gray-700 border border-gray-600 focus:outline-none focus:ring-2 focus:ring-blue-500"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder={authMode === 'ldap' ? 'LDAP password' : 'Boundary password'}
            />
          </div>
          <button
            type="submit"
            disabled={status.includes('...')}
            className="w-full p-2 rounded bg-blue-600 hover:bg-blue-700 font-bold transition-colors disabled:opacity-50"
          >
            {status.includes('...') ? status : (authMode === 'ldap' ? 'Login with LDAP' : 'Login')}
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
            <input
              type="text"
              className="p-2 rounded bg-gray-800 border border-gray-700 w-64 text-sm"
              value={targetId}
              onChange={(e) => setTargetId(e.target.value)}
              placeholder="Target ID (ttcp_...)"
            />
            <button
              onClick={handleConnect}
              disabled={status === 'Connected' || status.includes('...')}
              className="p-2 px-6 rounded bg-green-600 hover:bg-green-700 font-bold transition-colors text-sm disabled:opacity-50"
            >
              {status === 'Connected' ? 'Connected' : 'Connect'}
            </button>
          </div>
        </div>

        {error && <div className="mb-4 p-3 bg-red-900 border border-red-700 text-red-100 rounded text-sm">{error}</div>}

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
