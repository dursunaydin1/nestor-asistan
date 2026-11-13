// Sync engine for the spike (tech-architecture §10.3): push the outbox in order, then pull deltas.
import type { PostgrestError } from '@supabase/supabase-js';
import { supabase } from '../../data/supabase.ts';
import { db } from './db.ts';
import {
  isRetryable,
  nextCursor,
  pullSince,
  requestTimeoutMs,
  shouldApplyRemote,
  toLocal,
  type RemoteItem,
} from './merge.ts';

export type SyncReport = {
  at: string;
  pushed: number;
  pulled: number;
  // The server could not be reached; everything stays queued for the next run
  offline: boolean;
  error?: string;
};

class RetryLater extends Error {}

function retryLater(error: PostgrestError): boolean {
  return isRetryable(error.code, navigator.onLine);
}

async function push(): Promise<number> {
  // A previous run may have stopped mid-request (tab closed); those entries go back in the queue
  await db.outbox.where('status').equals('sending').modify({ status: 'pending' });
  const entries = await db.outbox.where('status').equals('pending').sortBy('seq');
  let pushed = 0;

  for (const entry of entries) {
    if (entry.seq === undefined) continue;
    const seq = entry.seq;
    await db.outbox.update(seq, { status: 'sending' });

    const { data, error } = await supabase
      .rpc('spike_upsert', {
        p_id: entry.itemId,
        p_title: entry.title,
        p_deleted: entry.deleted,
        p_base_version: entry.baseVersion,
      })
      .abortSignal(AbortSignal.timeout(requestTimeoutMs));

    if (error) {
      if (retryLater(error)) {
        await db.outbox.update(seq, { status: 'pending' });
        throw new RetryLater(error.message);
      }
      await db.outbox.update(seq, { status: 'attention', error: error.message });
      continue;
    }

    const { item, overwritten } = data as { item: RemoteItem; overwritten: boolean };
    await db.transaction('rw', db.items, db.outbox, async () => {
      await db.outbox.delete(seq);
      // The user may have edited the item again while the request was in flight
      const newer = await db.outbox
        .where('itemId')
        .equals(entry.itemId)
        .filter((next) => next.status === 'pending')
        .first();
      if (newer?.seq !== undefined) {
        await db.outbox.update(newer.seq, { baseVersion: item.version });
        await db.items.update(entry.itemId, { version: item.version });
      } else {
        await db.items.put(toLocal(item, overwritten));
      }
    });
    pushed++;
  }
  return pushed;
}

async function pull(): Promise<number> {
  const cursor = (await db.meta.get('cursor'))?.value;
  const since = pullSince(cursor, Date.now());

  let query = supabase
    .from('spike_items')
    .select('id, title, version, updated_at, deleted_at')
    .order('updated_at')
    .order('id')
    .limit(1000);
  if (since) query = query.gt('updated_at', since);

  const { data, error } = await query.abortSignal(AbortSignal.timeout(requestTimeoutMs));
  if (error) {
    if (retryLater(error)) throw new RetryLater(error.message);
    throw new Error(error.message);
  }
  const rows = data as RemoteItem[];

  await db.transaction('rw', db.items, db.outbox, db.meta, async () => {
    // Read after the response: edits made while the request was in flight must not be overwritten
    const pendingIds = new Set((await db.outbox.toArray()).map((entry) => entry.itemId));
    // A cursor too old to trust: drop everything the server can resend, keep unsent edits
    if (cursor && since === null) {
      await db.items.filter((item) => !pendingIds.has(item.id)).delete();
    }
    for (const row of rows) {
      const local = await db.items.get(row.id);
      if (shouldApplyRemote(local, row, pendingIds.has(row.id))) await db.items.put(toLocal(row));
    }
    const next = nextCursor(cursor, rows);
    if (next) await db.meta.put({ key: 'cursor', value: next });
  });
  return rows.length;
}

let running: Promise<SyncReport> | null = null;

// Single flight: triggers (online, foreground, timer, button) share one run
export function syncNow(): Promise<SyncReport> {
  running ??= (async () => {
    const at = new Date().toISOString();
    if (!navigator.onLine) return { at, pushed: 0, pulled: 0, offline: true };
    try {
      const pushed = await push();
      const pulled = await pull();
      return { at, pushed, pulled, offline: false };
    } catch (error) {
      if (error instanceof RetryLater) return { at, pushed: 0, pulled: 0, offline: true };
      // Surface unexpected failures instead of leaving the page silently stale
      const message = error instanceof Error ? error.message : String(error);
      return { at, pushed: 0, pulled: 0, offline: false, error: message };
    }
  })().finally(() => {
    running = null;
  });
  return running;
}
