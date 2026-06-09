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

import React, { useState } from 'react';
import axios from 'axios';

export type AuthMethod = 'ldap' | 'password';

export interface LoginFormProps {
  ldapAuthMethodId: string;
  onLoginSuccess: (token: string) => void;
  status: string;
  setStatus: (s: string) => void;
  error: string | null;
  setError: (e: string | null) => void;
}

const LoginForm: React.FC<LoginFormProps> = ({
  ldapAuthMethodId,
  onLoginSuccess,
  status,
  setStatus,
  error,
  setError,
}) => {
  const [loginName, setLoginName] = useState('');
  const [password, setPassword] = useState('');
  const [authMethod, setAuthMethod] = useState<AuthMethod>('ldap');

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
      onLoginSuccess(resp.data.token);
      setStatus('Logged in');
    } catch (err: unknown) {
      const axErr = err as { response?: { data?: { error?: string } }; message?: string };
      const msg = axErr.response?.data?.error || axErr.response?.data || axErr.message;
      setError(`Login failed: ${typeof msg === 'object' ? JSON.stringify(msg) : msg}`);
      setStatus('Error');
    }
  };

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
            onChange={(e) => setAuthMethod(e.target.value as AuthMethod)}
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
};

export default LoginForm;
