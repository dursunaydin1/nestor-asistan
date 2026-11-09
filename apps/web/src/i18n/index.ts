// Minimal typed translator. The product is Turkish-only (PRD §12), so a library like i18next
// would only add bundle weight. Keys are checked at compile time against tr.json.
import tr from './tr.json';

type Messages = typeof tr;

type Leaves<T, Prefix extends string = ''> = {
  [K in keyof T & string]: T[K] extends string ? `${Prefix}${K}` : Leaves<T[K], `${Prefix}${K}.`>;
}[keyof T & string];

export type MessageKey = Leaves<Messages>;

export function t(key: MessageKey, params?: Record<string, string | number>): string {
  let node: unknown = tr;
  for (const part of key.split('.')) {
    node = (node as Record<string, unknown>)[part];
  }
  if (typeof node !== 'string') return key;
  if (!params) return node;
  return node.replace(/\{(\w+)\}/g, (match, name: string) =>
    name in params ? String(params[name]) : match,
  );
}
