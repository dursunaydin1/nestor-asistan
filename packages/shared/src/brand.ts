// Single source of the product name in code (CLAUDE.md rule 11, PRD D-11).
// UI copy lives in apps/web/src/i18n/tr.json; this is for non-UI places (manifest, emails, metadata).
// The name is never shortened, and AI features have no separate name.
export const brand = {
  name: 'Nestor Asistan',
  storeName: 'Nestor Asistan – Emlakçılar İçin',
  poweredBy: 'Powered by Nestor Asistan',
} as const;

export type Brand = typeof brand;
