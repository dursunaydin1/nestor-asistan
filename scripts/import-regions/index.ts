// Usage: pnpm regions:import <input.csv> <output.sql> [--force]
// Converts the F0-8 region source (CSV, see README.md) into a SQL seed file.
import { access, readFile, writeFile } from 'node:fs/promises';
import { basename } from 'node:path';
import { buildRegions, parseCsv, toSql } from './regions.ts';

const args = process.argv.slice(2);
const force = args.includes('--force');
const [input, output] = args.filter((arg) => arg !== '--force');

if (!input || !output) {
  console.error('Kullanım: pnpm regions:import <girdi.csv> <çıktı.sql> [--force]');
  process.exit(1);
}

const exists = await access(output).then(
  () => true,
  () => false,
);
if (exists && !force) {
  console.error(`${output} zaten var. Üzerine yazmak için --force ekleyin.`);
  process.exit(1);
}

const { regions, errors } = buildRegions(parseCsv(await readFile(input, 'utf8')));
if (errors.length > 0) {
  console.error(`${errors.length} hata bulundu, dosya yazılmadı:`);
  for (const error of errors.slice(0, 50)) console.error(`  - ${error}`);
  process.exit(1);
}

await writeFile(output, toSql(regions, basename(input)));
console.warn(
  `${output} yazıldı: ${regions.il.length} il, ${regions.ilce.length} ilçe, ${regions.mahalle.length} mahalle`,
);
