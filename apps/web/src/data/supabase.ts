// Browser Supabase client. Uses only the publishable key; every query runs as the signed-in user
// under RLS (CLAUDE.md rules 9, 12). Import lazily so the initial bundle stays small.
import { createClient } from '@supabase/supabase-js';

const url = import.meta.env.VITE_SUPABASE_URL;
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;

export const supabaseConfigured = Boolean(url && key);

// createClient throws on an empty URL; screens check supabaseConfigured before calling it
export const supabase = createClient(url || 'http://missing.invalid', key || 'missing', {
  auth: { persistSession: true, autoRefreshToken: true },
});
