import { describe, expect, it } from 'vitest';
import { buildApiUrl } from '../src/lib/api';

describe('buildApiUrl', () => {
  it('uses the provided base URL for absolute paths', () => {
    expect(buildApiUrl('http://localhost:3001', '/health')).toBe('http://localhost:3001/health');
  });

  it('returns a relative URL when no base URL is provided', () => {
    expect(buildApiUrl('', '/health')).toBe('/health');
  });
});
