import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import LoginForm from './LoginForm';

vi.mock('axios', () => ({
  default: {
    post: vi.fn(),
  },
}));

import axios from 'axios';
const mockedPost = vi.mocked(axios.post);

describe('LoginForm', () => {
  const defaultProps = {
    ldapAuthMethodId: 'amldap_test123',
    onLoginSuccess: vi.fn(),
    status: 'Ready',
    setStatus: vi.fn(),
    error: null,
    setError: vi.fn(),
  };

  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('should render login form in Ready state', () => {
    render(<LoginForm {...defaultProps} />);
    expect(screen.getByText('Comet Boundary Login')).toBeInTheDocument();
    expect(screen.getByText('Login')).toBeInTheDocument();
  });

  it('should show auth method selector with LDAP and Password options', () => {
    render(<LoginForm {...defaultProps} />);
    const select = screen.getByDisplayValue('LDAP');
    expect(select).toBeInTheDocument();
    expect(screen.getByText('Password (Admin)')).toBeInTheDocument();
  });

  it('should transition to Logging In state on submit', async () => {
    mockedPost.mockResolvedValueOnce({ data: { token: 'tok_abc' } });
    const user = userEvent.setup();
    render(<LoginForm {...defaultProps} />);

    await user.type(screen.getByPlaceholderText('e.g. alice'), 'alice');
    const passwordInput = screen.getByRole('textbox', { hidden: true }).closest('form')!.querySelector('input[type="password"]') as HTMLInputElement;
    await user.type(passwordInput, 'changeme');
    await user.click(screen.getByText('Login'));

    expect(defaultProps.setStatus).toHaveBeenCalledWith('Logging in...');
  });

  it('should call onLoginSuccess with token on successful login', async () => {
    mockedPost.mockResolvedValueOnce({ data: { token: 'tok_abc' } });
    const user = userEvent.setup();
    render(<LoginForm {...defaultProps} />);

    await user.type(screen.getByPlaceholderText('e.g. alice'), 'alice');
    const passwordInput = screen.getByPlaceholderText('e.g. alice').closest('form')!.querySelector('input[type="password"]') as HTMLInputElement;
    await user.type(passwordInput, 'changeme');
    await user.click(screen.getByText('Login'));

    expect(defaultProps.onLoginSuccess).toHaveBeenCalledWith('tok_abc');
    expect(defaultProps.setStatus).toHaveBeenCalledWith('Logged in');
  });

  it('should show error state on login failure', async () => {
    mockedPost.mockRejectedValueOnce({
      response: { data: { error: 'Invalid credentials' } },
    });
    const user = userEvent.setup();
    render(<LoginForm {...defaultProps} />);

    await user.type(screen.getByPlaceholderText('e.g. alice'), 'alice');
    const passwordInput = screen.getByPlaceholderText('e.g. alice').closest('form')!.querySelector('input[type="password"]') as HTMLInputElement;
    await user.type(passwordInput, 'wrong');
    await user.click(screen.getByText('Login'));

    expect(defaultProps.setError).toHaveBeenCalledWith(
      expect.stringContaining('Login failed')
    );
    expect(defaultProps.setStatus).toHaveBeenCalledWith('Error');
  });

  it('should display error banner when error prop is set', () => {
    render(<LoginForm {...defaultProps} error="Some error" />);
    expect(screen.getByText('Some error')).toBeInTheDocument();
  });

  it('should disable button when status contains ellipsis', () => {
    render(<LoginForm {...defaultProps} status="Logging in..." />);
    expect(screen.getByRole('button')).toBeDisabled();
  });
});
