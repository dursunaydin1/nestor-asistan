// Turkish-aware text normalization for search, matching and region names (CLAUDE.md rule 8).
// Plain toLowerCase() maps "I" to "i" and "İ" to "i̇"; tr-TR maps them to "ı" and "i".
export function normalizeTr(value: string): string {
  return value.normalize('NFC').trim().replace(/\s+/g, ' ').toLocaleLowerCase('tr-TR');
}
