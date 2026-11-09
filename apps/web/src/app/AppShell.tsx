import { Outlet } from 'react-router';
import { LogoMark } from '../brand/LogoMark.tsx';
import { t } from '../i18n/index.ts';
import { BottomNav } from './BottomNav.tsx';
import { CreateMenu } from './CreateMenu.tsx';

export function AppShell() {
  return (
    <div className="flex min-h-dvh flex-col">
      <header className="sticky top-0 z-20 bg-brand-800 pt-[env(safe-area-inset-top)] text-white">
        <div className="flex h-14 items-center gap-2.5 px-4">
          <LogoMark className="h-7 w-auto" />
          <span className="text-lg font-bold tracking-tight">{t('app.name')}</span>
        </div>
      </header>

      {/* Bottom padding keeps content clear of the nav bar and the floating create button */}
      <main className="flex-1 pb-[calc(var(--spacing-nav)+env(safe-area-inset-bottom)+5rem)]">
        <Outlet />
      </main>

      <CreateMenu />
      <BottomNav />
    </div>
  );
}
