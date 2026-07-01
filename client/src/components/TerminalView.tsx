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

import React, { useEffect, useRef } from 'react';
import { Terminal } from '@xterm/xterm';
import { FitAddon } from '@xterm/addon-fit';
import '@xterm/xterm/css/xterm.css';

export interface SSHSession {
  sessionId: string;
  authorizationToken: string;
  sshUser: string;
  sshPassword: string;
}

export interface TerminalViewProps {
  session: SSHSession;
  setStatus: (s: string) => void;
  setError: (e: string | null) => void;
}

const TerminalView: React.FC<TerminalViewProps> = ({ session, setStatus, setError }) => {
  const terminalRef = useRef<HTMLDivElement>(null);
  const xtermRef = useRef<Terminal | null>(null);
  const wsRef = useRef<WebSocket | null>(null);

  useEffect(() => {
    if (!terminalRef.current) return;

    let cancelled = false;

    setStatus('Connecting to WebSocket...');

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
      theme: { background: '#000000' },
    });
    const fitAddon = new FitAddon();
    term.loadAddon(fitAddon);
    term.open(terminalRef.current);
    fitAddon.fit();

    const protocol = window.location.protocol === 'https:' ? 'wss://' : 'ws://';
    const ws = new WebSocket(`${protocol}${window.location.host}/ws/ssh`);
    wsRef.current = ws;

    ws.onopen = () => {
      if (cancelled) return;
      setStatus('Negotiating SSH...');
      ws.send(JSON.stringify({
        token: session.authorizationToken,
        ssh_user: session.sshUser,
        ssh_password: session.sshPassword,
      }));
      // Send initial terminal dimensions to correct any default mismatch
      ws.send(JSON.stringify({
        type: 'resize',
        cols: term.cols,
        rows: term.rows,
      }));
    };

    ws.onmessage = (event) => {
      if (cancelled) return;
      const msg = JSON.parse(event.data);
      if (msg.type === 'data') {
        setStatus('Connected');
        term.write(msg.data);
      }
    };

    ws.onerror = () => {
      if (cancelled) return;
      setError('WebSocket connection failed');
      setStatus('Error');
    };

    ws.onclose = () => {
      if (cancelled) return;
      setStatus('Disconnected');
    };

    term.onData((data) => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({ type: 'data', data }));
      }
    });

    const resizeSubscription = term.onResize((size) => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({ type: 'resize', cols: size.cols, rows: size.rows }));
      }
    });

    xtermRef.current = term;

    const handleResize = () => fitAddon.fit();
    window.addEventListener('resize', handleResize);

    return () => {
      cancelled = true;
      window.removeEventListener('resize', handleResize);
      resizeSubscription.dispose();
      term.dispose();
      ws.close();
    };
  }, [session, setStatus, setError]);

  return (
    <div className="bg-black rounded-lg overflow-hidden border border-gray-800 shadow-2xl">
      <div
        ref={terminalRef}
        style={{ height: '600px', width: '100%' }}
        className="p-2"
      />
    </div>
  );
};

export default TerminalView;
