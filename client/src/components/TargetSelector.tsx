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

import React from 'react';

export interface BoundaryTarget {
  id: string;
  name?: string;
}

export interface BoundaryHost {
  id: string;
  name?: string;
  address?: string;
}

export interface TargetSelectorProps {
  targets: BoundaryTarget[];
  selectedTarget: string;
  onTargetChange: (targetId: string) => void;
  hosts: BoundaryHost[];
  selectedHost: string;
  onHostChange: (hostId: string) => void;
  status: string;
  onConnect: () => void;
}

const TargetSelector: React.FC<TargetSelectorProps> = ({
  targets,
  selectedTarget,
  onTargetChange,
  hosts,
  selectedHost,
  onHostChange,
  status,
  onConnect,
}) => {
  return (
    <div className="flex items-center gap-4">
      <select
        className="p-2 rounded bg-gray-800 border border-gray-700 w-48 text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
        value={selectedTarget}
        onChange={(e) => onTargetChange(e.target.value)}
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
            onChange={(e) => onHostChange(e.target.value)}
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
        onClick={onConnect}
        disabled={status === 'Connected' || status.includes('...') || (!!selectedTarget && status !== 'Hosts discovered' && status !== 'Target selected')}
        className="p-2 px-6 rounded bg-green-600 hover:bg-green-700 font-bold transition-colors text-sm disabled:opacity-50"
      >
        {status === 'Connected' ? 'Connected' : 'Connect'}
      </button>
    </div>
  );
};

export default TargetSelector;
