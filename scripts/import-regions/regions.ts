// Pure functions behind the region importer: CSV parsing, validation and SQL generation.
// Table and column names are provisional until the M1 migration creates the region tables.
import { normalizeTr } from '@app/shared';

export const csvColumns = [
  'il_kodu',
  'il',
  'ilce_kodu',
  'ilce',
  'mahalle_kodu',
  'mahalle',
] as const;

export const sqlTables = {
  il: { name: 'regions_il', columns: ['id', 'ad', 'ad_normalize'] },
  ilce: { name: 'regions_ilce', columns: ['id', 'ust_id', 'ad', 'ad_normalize'] },
  mahalle: { name: 'regions_mahalle', columns: ['id', 'ust_id', 'ad', 'ad_normalize'] },
} as const;

export type Region = { id: number; parentId: number | null; name: string; normalized: string };
export type Regions = { il: Region[]; ilce: Region[]; mahalle: Region[] };
export type BuildResult = { regions: Regions; errors: string[] };

// RFC 4180 subset: quoted fields, escaped quotes (""), CRLF or LF line endings, optional BOM
export function parseCsv(text: string): string[][] {
  const rows: string[][] = [];
  let row: string[] = [];
  let field = '';
  let quoted = false;
  const input = text.charCodeAt(0) === 0xfeff ? text.slice(1) : text;

  for (let i = 0; i < input.length; i++) {
    const char = input[i];
    if (quoted) {
      if (char === '"' && input[i + 1] === '"') {
        field += '"';
        i++;
      } else if (char === '"') {
        quoted = false;
      } else {
        field += char;
      }
    } else if (char === '"') {
      quoted = true;
    } else if (char === ',') {
      row.push(field);
      field = '';
    } else if (char === '\n' || char === '\r') {
      if (char === '\r' && input[i + 1] === '\n') i++;
      row.push(field);
      rows.push(row);
      row = [];
      field = '';
    } else {
      field += char;
    }
  }
  if (field !== '' || row.length > 0) {
    row.push(field);
    rows.push(row);
  }
  return rows.filter((r) => r.some((value) => value.trim() !== ''));
}

function parseCode(value: string): number | null {
  return /^\d+$/.test(value.trim()) ? Number(value.trim()) : null;
}

// One CSV row per neighbourhood; il and ilçe repeat on every row and must stay consistent
export function buildRegions(rows: string[][]): BuildResult {
  const errors: string[] = [];
  const regions: Regions = { il: [], ilce: [], mahalle: [] };
  const [header, ...body] = rows;

  if (!header || header.map((h) => h.trim()).join(',') !== csvColumns.join(',')) {
    return { regions, errors: [`Başlık satırı tam olarak şu olmalı: ${csvColumns.join(',')}`] };
  }

  const seen = { il: new Map<number, Region>(), ilce: new Map<number, Region>() };
  const mahalleIds = new Set<number>();

  body.forEach((cells, index) => {
    const line = index + 2;
    if (cells.length !== csvColumns.length) {
      errors.push(
        `Satır ${line}: ${csvColumns.length} sütun bekleniyordu, ${cells.length} bulundu`,
      );
      return;
    }
    const [ilCode, ilName, ilceCode, ilceName, mahalleCode, mahalleName] = cells.map((c) =>
      c.trim().replace(/\s+/g, ' '),
    ) as [string, string, string, string, string, string];
    const ilId = parseCode(ilCode);
    const ilceId = parseCode(ilceCode);
    const mahalleId = parseCode(mahalleCode);
    if (ilId === null || ilceId === null || mahalleId === null) {
      errors.push(`Satır ${line}: kodlar pozitif tam sayı olmalı`);
      return;
    }
    if (!ilName || !ilceName || !mahalleName) {
      errors.push(`Satır ${line}: il, ilçe ve mahalle adları boş olamaz`);
      return;
    }

    const il = seen.il.get(ilId);
    if (!il) {
      const region = { id: ilId, parentId: null, name: ilName, normalized: normalizeTr(ilName) };
      seen.il.set(ilId, region);
      regions.il.push(region);
    } else if (il.name !== ilName) {
      errors.push(`Satır ${line}: il kodu ${ilId} hem "${il.name}" hem "${ilName}" olarak geçiyor`);
    }

    const ilce = seen.ilce.get(ilceId);
    if (!ilce) {
      const region = {
        id: ilceId,
        parentId: ilId,
        name: ilceName,
        normalized: normalizeTr(ilceName),
      };
      seen.ilce.set(ilceId, region);
      regions.ilce.push(region);
    } else if (ilce.name !== ilceName || ilce.parentId !== ilId) {
      errors.push(`Satır ${line}: ilçe kodu ${ilceId} farklı ad veya ille tekrar ediyor`);
    }

    if (mahalleIds.has(mahalleId)) {
      errors.push(`Satır ${line}: mahalle kodu ${mahalleId} tekrar ediyor`);
      return;
    }
    mahalleIds.add(mahalleId);
    regions.mahalle.push({
      id: mahalleId,
      parentId: ilceId,
      name: mahalleName,
      normalized: normalizeTr(mahalleName),
    });
  });

  return { regions, errors };
}

function sqlString(value: string): string {
  return `'${value.replaceAll("'", "''")}'`;
}

function insert(table: { name: string; columns: readonly string[] }, values: string[]): string {
  if (values.length === 0) return '';
  return `insert into ${table.name} (${table.columns.join(', ')}) values\n  ${values.join(',\n  ')};\n`;
}

export function toSql({ il, ilce, mahalle }: Regions, source: string): string {
  const row = (r: Region) =>
    [
      String(r.id),
      ...(r.parentId === null ? [] : [String(r.parentId)]),
      sqlString(r.name),
      sqlString(r.normalized),
    ].join(', ');
  return [
    `-- Generated by scripts/import-regions from ${source}. Do not edit by hand.`,
    `-- ${il.length} il, ${ilce.length} ilçe, ${mahalle.length} mahalle`,
    'begin;',
    insert(
      sqlTables.il,
      il.map((r) => `(${row(r)})`),
    ),
    insert(
      sqlTables.ilce,
      ilce.map((r) => `(${row(r)})`),
    ),
    insert(
      sqlTables.mahalle,
      mahalle.map((r) => `(${row(r)})`),
    ),
    'commit;',
    '',
  ].join('\n');
}
