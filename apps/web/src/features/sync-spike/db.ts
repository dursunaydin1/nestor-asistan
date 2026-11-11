// Local store for the sync spike: items, the outbox of unsent writes, and the pull cursor.
import Dexie, { type EntityTable } from 'dexie';
import type { LocalItem } from './merge.ts';

// pending: waiting to be sent · sending: request in flight · attention: rejected by the server
export type OutboxStatus = 'pending' | 'sending' | 'attention';

export type OutboxEntry = {
  seq?: number;
  itemId: string;
  title: string;
  deleted: boolean;
  // Server version the edit was based on; null for items the server has never seen
  baseVersion: number | null;
  status: OutboxStatus;
  error?: string;
};

type Meta = { key: string; value: string };

class SpikeDb extends Dexie {
  items!: EntityTable<LocalItem, 'id'>;
  outbox!: EntityTable<OutboxEntry, 'seq'>;
  meta!: EntityTable<Meta, 'key'>;

  constructor() {
    super('sync-spike');
    this.version(1).stores({
      items: 'id, updatedAt',
      outbox: '++seq, itemId, status',
      meta: 'key',
    });
  }
}

export const db = new SpikeDb();

// Writes locally first, then queues the change. Edits to an item that is still waiting are folded
// into its pending entry so the server sees one write based on the right version.
export async function saveLocal(id: string, title: string, deleted: boolean): Promise<void> {
  await db.transaction('rw', db.items, db.outbox, async () => {
    const local = await db.items.get(id);
    const now = new Date().toISOString();
    await db.items.put({
      id,
      title,
      version: local?.version ?? 0,
      updatedAt: now,
      deletedAt: deleted ? now : null,
    });
    const pending = await db.outbox
      .where('itemId')
      .equals(id)
      .filter((entry) => entry.status === 'pending')
      .first();
    if (pending?.seq !== undefined) {
      await db.outbox.update(pending.seq, { title, deleted });
    } else {
      await db.outbox.add({
        itemId: id,
        title,
        deleted,
        baseVersion: local && local.version > 0 ? local.version : null,
        status: 'pending',
      });
    }
  });
}

export async function clearLocal(): Promise<void> {
  await Promise.all([db.items.clear(), db.outbox.clear(), db.meta.clear()]);
}
