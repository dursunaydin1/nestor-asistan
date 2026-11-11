import { describe, expect, it } from 'vitest';
import {
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

describe('nextCursor', () => {
  it('keeps the latest updated_at seen', () => {
    const rows = [remote(1, '2026-11-11T10:00:00.000Z'), remote(2, '2026-11-11T10:05:00.000Z')];
    expect(nextCursor('2026-11-11T09:00:00.000Z', rows)).toBe('2026-11-11T10:05:00.000Z');
    expect(nextCursor('2026-11-11T11:00:00.000Z', rows)).toBe('2026-11-11T11:00:00.000Z');
    expect(nextCursor(undefined, [])).toBeUndefined();
  });
});
