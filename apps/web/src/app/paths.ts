// Route paths are Turkish because they are visible to users in shared links and the address bar
export const paths = {
  today: '/bugun',
  query: '/sorgula',
  portfolio: '/portfoy',
  customers: '/musteriler',
  more: '/daha-fazla',
  // Not linked from the UI; used to check device capabilities (M0 step 8, ADR-0002)
  diagnostics: '/tani',
} as const;
