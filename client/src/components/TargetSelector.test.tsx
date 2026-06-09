import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import TargetSelector from './TargetSelector';

describe('TargetSelector', () => {
  const defaultProps = {
    targets: [
      { id: 'ttcp_A', name: 'A Team Host' },
      { id: 'ttcp_B', name: 'B Team Host' },
    ],
    selectedTarget: '',
    onTargetChange: vi.fn(),
    hosts: [],
    selectedHost: '',
    onHostChange: vi.fn(),
    status: 'Targets discovered',
    onConnect: vi.fn(),
  };

  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('should render target dropdown with discovered targets', () => {
    render(<TargetSelector {...defaultProps} />);
    expect(screen.getByText('A Team Host')).toBeInTheDocument();
    expect(screen.getByText('B Team Host')).toBeInTheDocument();
  });

  it('should call onTargetChange when a target is selected', async () => {
    const user = userEvent.setup();
    render(<TargetSelector {...defaultProps} />);
    const select = screen.getByDisplayValue('Select Target...');
    await user.selectOptions(select, 'ttcp_A');
    expect(defaultProps.onTargetChange).toHaveBeenCalledWith('ttcp_A');
  });

  it('should show host dropdown when target selected and multiple hosts exist', () => {
    render(
      <TargetSelector
        {...defaultProps}
        selectedTarget="ttcp_A"
        hosts={[
          { id: 'hst_1', name: 'ssh-host-1' },
          { id: 'hst_2', name: 'ssh-host-2' },
        ]}
        status="Hosts discovered"
      />
    );
    expect(screen.getByText('ssh-host-1')).toBeInTheDocument();
    expect(screen.getByText('ssh-host-2')).toBeInTheDocument();
  });

  it('should hide host dropdown when only one host exists', () => {
    render(
      <TargetSelector
        {...defaultProps}
        selectedTarget="ttcp_A"
        hosts={[{ id: 'hst_1', name: 'ssh-host-1' }]}
        status="Hosts discovered"
      />
    );
    expect(screen.queryByText('ssh-host-1')).not.toBeInTheDocument();
  });

  it('should show loading indicator during host discovery', () => {
    render(
      <TargetSelector
        {...defaultProps}
        selectedTarget="ttcp_A"
        status="Discovering hosts..."
      />
    );
    expect(screen.getByText('Loading Hosts...')).toBeInTheDocument();
  });

  it('should disable Connect button when already connected', () => {
    render(<TargetSelector {...defaultProps} status="Connected" />);
    expect(screen.getByText('Connected')).toBeDisabled();
  });

  it('should call onConnect when Connect clicked', async () => {
    const user = userEvent.setup();
    render(
      <TargetSelector
        {...defaultProps}
        selectedTarget="ttcp_A"
        status="Hosts discovered"
      />
    );
    await user.click(screen.getByText('Connect'));
    expect(defaultProps.onConnect).toHaveBeenCalled();
  });

  it('should disable target dropdown when discovering targets', () => {
    render(<TargetSelector {...defaultProps} status="Discovering targets..." />);
    const select = screen.getByDisplayValue('Loading Targets...');
    expect(select).toBeDisabled();
  });
});
