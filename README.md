# Nestor

**Emlakçının asistanı.** Emlak ofisleri için telefondan, sahada ve internet olmadan da çalışan portföy, müşteri ve talep yönetimi; talep ile mülkü otomatik eşleştirme; hatırlatmalar; vitrin, QR ve belgeler; yapay zekâ destekli Nestor Asistan.

> Durum: geliştirme başlangıcı (M0). Pilot hedefi: 22 Şubat 2027.

## Belgeler

Ürün ve planlama belgeleri bu depoda yayımlanmaz.

## Yığın

Vite + React 19 + TypeScript + Tailwind (PWA) · Supabase (Postgres, Auth, Storage, RLS, Edge Functions) · Dexie (IndexedDB) · Cloudflare Pages · Resend · Vitest + Playwright

## Depo yapısı (hedef)

```
nestor-asistan/
  apps/web/          # PWA
  apps/public/       # herkese açık sayfalar (/p, /q)
  packages/shared/   # tipler, zod şemaları, eşleştirme, brand.ts
  supabase/          # migrations, functions, tests, seed
  scripts/           # bölge verisi, sentetik veri
  e2e/               # Playwright
```

## Kurulum

M0 tamamlanınca eklenecek (Node LTS, pnpm, Supabase CLI).
