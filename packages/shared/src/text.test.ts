import { describe, expect, it } from 'vitest';
import { normalizeTr } from './text.ts';

describe('normalizeTr', () => {
  it('lowercases dotted and dotless I the Turkish way', () => {
    expect(normalizeTr('İSTANBUL')).toBe('istanbul');
    expect(normalizeTr('IĞDIR')).toBe('ığdır');
    expect(normalizeTr('ÇANAKKALE ŞİLE ÜSKÜDAR ÖDEMİŞ')).toBe('çanakkale şile üsküdar ödemiş');
  });

  it('trims and collapses whitespace', () => {
    expect(normalizeTr('  Kadıköy \t  Merkez ')).toBe('kadıköy merkez');
  });

  it('treats decomposed and composed characters the same', () => {
    expect(normalizeTr('Bağcılar')).toBe(normalizeTr('Bağcılar'));
  });
});
