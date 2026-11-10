import { render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router';
import { describe, expect, it } from 'vitest';
import { t } from '../i18n/index.ts';
import { BottomNav } from './BottomNav.tsx';
import { paths } from './paths.ts';

function renderAt(path: string) {
  render(
    <MemoryRouter initialEntries={[path]}>
      <BottomNav />
    </MemoryRouter>,
  );
  return screen.getByRole('navigation', { name: t('nav.label') });
}

describe('BottomNav', () => {
  it('shows the five PRD §12.1 tabs in order', () => {
    const nav = renderAt(paths.today);
    const links = within(nav).getAllByRole('link');
    expect(links.map((link) => link.textContent)).toEqual([
      t('nav.today'),
      t('nav.query'),
      t('nav.portfolio'),
      t('nav.customers'),
      t('nav.more'),
    ]);
    expect(links.map((link) => link.getAttribute('href'))).toEqual([
      paths.today,
      paths.query,
      paths.portfolio,
      paths.customers,
      paths.more,
    ]);
  });

  it('marks only the current tab as active', () => {
    const nav = renderAt(paths.portfolio);
    const active = within(nav).getByRole('link', { current: 'page' });
    expect(active).toHaveTextContent(t('nav.portfolio'));
    expect(within(nav).getAllByRole('link', { current: false })).toHaveLength(4);
  });
});
