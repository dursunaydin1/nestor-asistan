import { brand } from '@app/shared';
import tailwindcss from '@tailwindcss/vite';
import react from '@vitejs/plugin-react';
import { defineConfig, type Plugin } from 'vite';
import { VitePWA } from 'vite-plugin-pwa';
import { brandColors } from './src/brand/logo.ts';
import tr from './src/i18n/tr.json' with { type: 'json' };

// index.html must not hardcode the product name (CLAUDE.md rule 11)
function brandHtml(): Plugin {
  return {
    name: 'brand-html',
    transformIndexHtml: (html) =>
      html
        .replaceAll('%BRAND_NAME%', brand.name)
        .replaceAll('%BRAND_DESCRIPTION%', tr.app.description)
        .replaceAll('%THEME_COLOR%', brandColors.navy),
  };
}

export default defineConfig({
  plugins: [
    react(),
    tailwindcss(),
    brandHtml(),
    VitePWA({
      registerType: 'autoUpdate',
      injectRegister: 'auto',
      includeAssets: ['favicon.svg', 'apple-touch-icon-180x180.png'],
      manifest: {
        name: brand.name,
        short_name: brand.name,
        description: tr.app.description,
        lang: 'tr',
        dir: 'ltr',
        start_url: '/',
        scope: '/',
        display: 'standalone',
        orientation: 'portrait',
        theme_color: brandColors.navy,
        background_color: brandColors.canvas,
        icons: [
          { src: 'pwa-64x64.png', sizes: '64x64', type: 'image/png' },
          { src: 'pwa-192x192.png', sizes: '192x192', type: 'image/png' },
          { src: 'pwa-512x512.png', sizes: '512x512', type: 'image/png' },
          {
            src: 'maskable-icon-512x512.png',
            sizes: '512x512',
            type: 'image/png',
            purpose: 'maskable',
          },
        ],
      },
      workbox: {
        // App shell only; font files outside the Turkish subsets (latin, latin-ext) are skipped
        globPatterns: [
          '**/*.{js,css,html,svg,png}',
          '**/*-latin-wght-normal*.woff2',
          '**/*-latin-ext-wght-normal*.woff2',
        ],
        navigateFallback: '/index.html',
      },
    }),
  ],
});
