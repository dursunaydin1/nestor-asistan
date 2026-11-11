/// <reference types="vite/client" />

// Public by design (RLS protects data); set in .env locally and in Cloudflare Pages settings
interface ImportMetaEnv {
  readonly VITE_SUPABASE_URL?: string;
  readonly VITE_SUPABASE_PUBLISHABLE_KEY?: string;
}
