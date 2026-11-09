// Single source of the brand mark: used by the <LogoMark> component and scripts/generate-icons.ts.
// Concept: an amber roof (home, keys, warmth) over a white "N" monogram on deep navy (trust, a
// steady advisor). Geometry is drawn on a 512×512 grid and centered on (256, 256).
// Keep these colors in sync with --color-brand-800 / --color-accent-400 in src/index.css.
export const brandColors = {
  navy: '#0E2A47',
  amber: '#F2A33A',
  white: '#FFFFFF',
  // Light app background, used for the manifest splash screen
  canvas: '#F5F7FA',
} as const;

export const markPaths = {
  // Chevron roof with vertical eaves; perpendicular thickness ≈ the monogram stems
  roof: 'M256 101 L420 235.5 V287.5 L256 153 L92 287.5 V235.5 Z',
  // Geometric N with flat terminals; the diagonal is slightly heavier than the stems
  monogram: 'M146 271 H211 L326 374.9 V271 H366 V411 H301 L186 307.1 V411 H146 Z',
} as const;

// Tight bounds of the mark (x 92–420, y 101–411) with a small margin, for inline use
export const markViewBox = '84 93 344 326';
