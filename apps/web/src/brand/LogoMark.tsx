import { brandColors, markPaths, markViewBox } from './logo.ts';

type LogoMarkProps = {
  className?: string;
};

// Decorative: the product name is always rendered next to it as text from tr.json.
// The monogram follows `currentColor` so the mark works on both navy and light surfaces.
export function LogoMark({ className }: LogoMarkProps) {
  return (
    <svg viewBox={markViewBox} aria-hidden="true" focusable="false" className={className}>
      <path d={markPaths.roof} fill={brandColors.amber} />
      <path d={markPaths.monogram} fill="currentColor" />
    </svg>
  );
}
