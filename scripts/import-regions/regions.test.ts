import { readFile } from 'node:fs/promises';
import { describe, expect, it } from 'vitest';
import { buildRegions, csvColumns, parseCsv, toSql } from './regions.ts';

const header = csvColumns.join(',');

describe('parseCsv', () => {
  it('handles BOM, CRLF, quotes and escaped quotes', () => {
    const bom = String.fromCharCode(0xfeff);
    expect(parseCsv(`${bom}a,b\r\n"x, y","say ""hi"""\r\n`)).toEqual([
      ['a', 'b'],
      ['x, y', 'say "hi"'],
    ]);
  });
});

describe('buildRegions', () => {
  it('builds the il → ilçe → mahalle hierarchy from the sample file', async () => {
    const csv = await readFile(new URL('./fixtures/sample.csv', import.meta.url), 'utf8');
    const { regions, errors } = buildRegions(parseCsv(csv));
    expect(errors).toEqual([]);
    expect(regions.il.map((r) => r.normalized)).toEqual(['istanbul', 'ığdır']);
    expect(regions.ilce).toHaveLength(3);
    expect(regions.mahalle).toHaveLength(4);
    expect(regions.mahalle[0]).toEqual({
      id: 100101,
      parentId: 1001,
      name: 'Caferağa',
      normalized: 'caferağa',
    });
  });

  it('rejects a wrong header', () => {
    expect(buildRegions([['il', 'ilce']]).errors).toHaveLength(1);
  });

  it('reports inconsistent names, duplicates and bad codes with line numbers', () => {
    const { errors } = buildRegions(
      parseCsv(
        [
          header,
          '34,İSTANBUL,1001,KADIKÖY,100101,Moda',
          '34,ISTANBUL,1001,KADIKÖY,100102,Caferağa',
          '34,İSTANBUL,1001,KADIKÖY,100101,Fenerbahçe',
          'x,İSTANBUL,1001,KADIKÖY,100103,Göztepe',
        ].join('\n'),
      ),
    );
    expect(errors).toEqual([
      expect.stringMatching(/^Satır 3: il kodu 34/),
      expect.stringMatching(/^Satır 4: mahalle kodu 100101/),
      expect.stringMatching(/^Satır 5: kodlar/),
    ]);
  });
});

describe('toSql', () => {
  it('escapes quotes and wraps inserts in a transaction', () => {
    const { regions } = buildRegions(parseCsv(`${header}\n1,A,10,B,100,O'Neil`));
    const sql = toSql(regions, 'test.csv');
    expect(sql).toContain("(100, 10, 'O''Neil', 'o''neil')");
    expect(sql.trim().startsWith('-- Generated')).toBe(true);
    expect(sql).toMatch(/begin;[\s\S]*commit;/);
  });
});
