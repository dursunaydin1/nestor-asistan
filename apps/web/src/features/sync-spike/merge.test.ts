import { describe, expect, it } from 'vitest';
import {
  isReachable,
  isRetryable,
  nextCursor,
  pullOverlapMs,
  pullSince,
  shouldApplyRemote,
  staleCursorMs,
  toLocal,
  type RemoteItem,
} from './merge.ts';

const remote = (version: number, updated_at = '2026-11-11T10:00:00.000Z'): RemoteItem => ({
  id: 'a',
  title: `v${version}`,
  version,
  updated_at,
  deleted_at: null,
});

describe('shouldApplyRemote', () => {
  it('applies unknown rows and newer versions', () => {
    expect(shouldApplyRemote(undefined, remote(1), false)).toBe(true);
    expect(shouldApplyRemote(toLocal(remote(1)), remote(2), false)).toBe(true);
  });

  it('ignores duplicates and older versions from the overlap window', () => {
    expect(shouldApplyRemote(toLocal(remote(2)), remote(2), false)).toBe(false);
    expect(shouldApplyRemote(toLocal(remote(3)), remote(2), false)).toBe(false);
  });

  it('never replaces a local edit waiting in the outbox', () => {
    expect(shouldApplyRemote(toLocal(remote(1)), remote(5), true)).toBe(false);
  });
});

describe('pullSince', () => {
  const now = Date.parse('2026-11-11T12:00:00.000Z');

  it('pulls everything on first sync', () => {
    expect(pullSince(undefined, now)).toBeNull();
  });

  it('rewinds the cursor by the overlap window', () => {
    const cursor = '2026-11-11T11:00:00.000Z';
    expect(pullSince(cursor, now)).toBe(new Date(Date.parse(cursor) - pullOverlapMs).toISOString());
  });

  it('pulls everything again when the cursor is too old to trust', () => {
    const old = new Date(now - staleCursorMs - 1).toISOString();
    expect(pullSince(old, now)).toBeNull();
  });
});

describe('isRetryable', () => {
  it('retries requests that got no response, including timeouts', () => {
    expect(isRetryable('', true)).toBe(true);
    expect(isRetryable(undefined, true)).toBe(true);
    expect(isRetryable('23514', false)).toBe(true);
  });

  it('retries auth errors that a token refresh fixes', () => {
    expect(isRetryable('PGRST301', true)).toBe(true);
  });

  it('marks real server rejections for attention', () => {
    expect(isRetryable('23514', true)).toBe(false);
    expect(isRetryable('42501', true)).toBe(false);
  });
});

describe('isReachable', () => {
  it('trusts the last sync over navigator.onLine, which stays true behind a VPN', () => {
    expect(isReachable(true, undefined)).toBe(true);
    expect(isReachable(true, false)).toBe(true);
    expect(isReachable(true, true)).toBe(false);
    expect(isReachable(false, false)).toBe(false);
  });
});

describe('nextCursor', () => {
  it('keeps the latest updated_at seen', () => {
    const rows = [remote(1, '2026-11-11T10:00:00.000Z'), remote(2, '2026-11-11T10:05:00.000Z')];
    expect(nextCursor('2026-11-11T09:00:00.000Z', rows)).toBe('2026-11-11T10:05:00.000Z');
    expect(nextCursor('2026-11-11T11:00:00.000Z', rows)).toBe('2026-11-11T11:00:00.000Z');
    expect(nextCursor(undefined, [])).toBeUndefined();
  });
});
