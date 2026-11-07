// Single source of the product name in code (CLAUDE.md rule 11, PRD D-11).
// UI copy lives in apps/web/src/i18n/tr.json; this is for non-UI places (manifest, emails, metadata).
export const brand = {
  name: 'Nestor',
  assistantName: 'Nestor Asistan',
  storeName: 'Nestor – Emlakçının Asistanı',
  poweredBy: 'Powered by Nestor',
} as const;

export type Brand = typeof brand;
