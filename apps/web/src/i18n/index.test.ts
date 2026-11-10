import { brand } from '@app/shared';
import { describe, expect, it } from 'vitest';
import { t, type MessageKey } from './index.ts';
import tr from './tr.json';

function leaves(node: unknown, prefix = ''): [string, unknown][] {
  if (typeof node !== 'object' || node === null) return [[prefix, node]];
  return Object.entries(node).flatMap(([key, value]) =>
    leaves(value, prefix ? `${prefix}.${key}` : key),
  );
}

describe('t()', () => {
  it('resolves nested keys from tr.json', () => {
    expect(t('nav.today')).toBe('Bugün');
    expect(t('pages.portfolio.emptyTitle')).toBe('Portföyünüz henüz boş');
  });

  it('falls back to the key when a message is missing', () => {
    expect(t('nav.unknown' as MessageKey)).toBe('nav.unknown');
    expect(t('nav' as MessageKey)).toBe('nav');
  });
});

describe('tr.json', () => {
  it('has only non-empty string messages', () => {
    for (const [key, value] of leaves(tr)) {
      expect(typeof value, key).toBe('string');
      expect((value as string).trim(), key).not.toBe('');
    }
  });

  // CLAUDE.md rule 11: the name lives in brand.ts and tr.json, and the two must agree
  it('uses the same product name as brand.ts', () => {
    expect(tr.app.name).toBe(brand.name);
  });
});
