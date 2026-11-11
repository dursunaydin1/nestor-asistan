// Pure sync rules from tech-architecture §10.3, kept free of I/O so they can be unit tested.

export type RemoteItem = {
  id: string;
  title: string;
  version: number;
  updated_at: string;
  deleted_at: string | null;
};

export type LocalItem = {
  id: string;
  title: string;
  // 0 until the server has accepted the item
  version: number;
  updatedAt: string;
  deletedAt: string | null;
  overwritten?: boolean;
};

// updated_at is set at transaction start but visible only after commit, so re-read a window
export const pullOverlapMs = 5 * 60 * 1000;
// Tombstones are purged after 30 days; a cursor older than this cannot trust deltas
export const staleCursorMs = 25 * 24 * 60 * 60 * 1000;

export function toLocal(remote: RemoteItem, overwritten = false): LocalItem {
  return {
    id: remote.id,
    title: remote.title,
    version: remote.version,
    updatedAt: remote.updated_at,
    deletedAt: remote.deleted_at,
    ...(overwritten ? { overwritten } : {}),
  };
}

// Rows may arrive twice because of the overlap window. Keep the newer version, and never
// replace a local edit that is still waiting in the outbox.
export function shouldApplyRemote(
  local: LocalItem | undefined,
  remote: RemoteItem,
  hasPendingWrite: boolean,
): boolean {
  if (hasPendingWrite) return false;
  return !local || remote.version > local.version;
}

// null means "pull everything": first sync, or a cursor too old to trust
export function pullSince(cursor: string | undefined, now: number): string | null {
  if (!cursor) return null;
  const time = Date.parse(cursor);
  if (Number.isNaN(time) || now - time > staleCursorMs) return null;
  return new Date(time - pullOverlapMs).toISOString();
}

export function nextCursor(current: string | undefined, rows: RemoteItem[]): string | undefined {
  return rows.reduce<string | undefined>(
    (max, row) => (!max || Date.parse(row.updated_at) > Date.parse(max) ? row.updated_at : max),
    current,
  );
}
