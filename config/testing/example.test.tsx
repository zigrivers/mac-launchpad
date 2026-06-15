// Sample component test (Vitest + Testing Library). Replace <Button> with a
// real component. Run with: npm test
import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';

// A tiny inline component so this file runs as-is; delete it and import yours.
function Button({ children }: { children: React.ReactNode }) {
  return <button>{children}</button>;
}

describe('Button', () => {
  it('renders its label', () => {
    render(<Button>Click me</Button>);
    expect(screen.getByRole('button', { name: 'Click me' })).toBeInTheDocument();
  });
});
