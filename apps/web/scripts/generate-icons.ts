// Generates favicon, PWA and Apple touch icons from the brand mark in src/brand/logo.ts.
// Run with `pnpm --filter @app/web icons`; the output in public/ is committed.
import { mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';
import { brandColors, markPaths } from '../src/brand/logo.ts';

const publicDir = fileURLToPath(new URL('../public/', import.meta.url));

function mark(scale: number, monogramColor: string = brandColors.white): string {
  return (
    `<g transform="translate(256 256) scale(${scale}) translate(-256 -256)">` +
    `<path d="${markPaths.roof}" fill="${brandColors.amber}"/>` +
    `<path d="${markPaths.monogram}" fill="${monogramColor}"/>` +
    `</g>`
  );
}

function svg(body: string): string {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512">${body}</svg>`;
}

// "any" purpose: rounded tile, used as favicon and standard PWA icon
const tile = svg(
  `<rect width="512" height="512" rx="112" fill="${brandColors.navy}"/>${mark(0.9)}`,
);
// Full-bleed square: the OS applies its own mask. The mark stays inside the 80% safe-zone circle.
const maskable = svg(`<rect width="512" height="512" fill="${brandColors.navy}"/>${mark(0.85)}`);
// iOS rounds the corners itself and does not accept transparency
const apple = svg(`<rect width="512" height="512" fill="${brandColors.navy}"/>${mark(0.9)}`);
// Transparent mark for documents and light backgrounds
const markOnly = svg(mark(1, brandColors.navy));

const pngs: [name: string, source: string, size: number][] = [
  ['pwa-64x64.png', tile, 64],
  ['pwa-192x192.png', tile, 192],
  ['pwa-512x512.png', tile, 512],
  ['maskable-icon-512x512.png', maskable, 512],
  ['apple-touch-icon-180x180.png', apple, 180],
];

await mkdir(publicDir, { recursive: true });
await writeFile(`${publicDir}favicon.svg`, tile);
await writeFile(`${publicDir}logo-mark.svg`, markOnly);
for (const [name, source, size] of pngs) {
  await sharp(Buffer.from(source), { density: 300 })
    .resize(size, size)
    .png({ compressionLevel: 9 })
    .toFile(`${publicDir}${name}`);
}
console.warn(`Icons written to ${publicDir}`);
