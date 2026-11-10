// Minimal typed translator. The product is Turkish-only (PRD §12), so a library like i18next
// would only add bundle weight. Keys are checked at compile time against tr.json.
import tr from './tr.json';

type Messages = typeof tr;

type Leaves<T, Prefix extends string = ''> = {
  [K in keyof T & string]: T[K] extends string ? `${Prefix}${K}` : Leaves<T[K], `${Prefix}${K}.`>;
}[keyof T & string];

export type MessageKey = Leaves<Messages>;

// Falls back to the key itself so a missing message is visible rather than blank
export function t(key: MessageKey): string {
  let node: unknown = tr;
  for (const part of key.split('.')) {
    node = (node as Record<string, unknown> | undefined)?.[part];
  }
  return typeof node === 'string' ? node : key;
}
