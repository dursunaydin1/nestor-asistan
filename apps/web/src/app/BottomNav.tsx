import { Building2, CalendarCheck, Menu, Search, Users, type LucideIcon } from 'lucide-react';
import { NavLink } from 'react-router';
import { t, type MessageKey } from '../i18n/index.ts';
import { paths } from './paths.ts';

type Tab = { to: string; label: MessageKey; icon: LucideIcon };

// Order and labels follow PRD §12.1
const tabs: Tab[] = [
  { to: paths.today, label: 'nav.today', icon: CalendarCheck },
  { to: paths.query, label: 'nav.query', icon: Search },
  { to: paths.portfolio, label: 'nav.portfolio', icon: Building2 },
  { to: paths.customers, label: 'nav.customers', icon: Users },
  { to: paths.more, label: 'nav.more', icon: Menu },
];

export function BottomNav() {
  return (
    <nav
      aria-label={t('nav.label')}
      className="fixed inset-x-0 bottom-0 z-20 border-t border-slate-200 bg-white pb-[env(safe-area-inset-bottom)]"
    >
      <ul className="mx-auto grid h-nav max-w-lg grid-cols-5">
        {tabs.map(({ to, label, icon: Icon }) => (
          <li key={to}>
            <NavLink
              to={to}
              className={({ isActive }) =>
                `relative flex h-full flex-col items-center justify-center gap-1 text-[11px] font-medium ${
                  isActive ? 'text-brand-800' : 'text-slate-600'
                }`
              }
            >
              {({ isActive }) => (
                <>
                  {isActive && (
                    <span
                      className="absolute top-0 h-1 w-8 rounded-b-full bg-accent-400"
                      aria-hidden="true"
                    />
                  )}
                  <Icon
                    className="size-6"
                    strokeWidth={isActive ? 2.25 : 1.75}
                    aria-hidden="true"
                  />
                  <span className={isActive ? 'font-semibold' : undefined}>{t(label)}</span>
                </>
              )}
            </NavLink>
          </li>
        ))}
      </ul>
    </nav>
  );
}
