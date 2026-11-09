import { Building2 } from 'lucide-react';
import { EmptyState } from '../../components/EmptyState.tsx';
import { PageHeader } from '../../components/PageHeader.tsx';
import { t } from '../../i18n/index.ts';

// Property list, filters and status tabs arrive in M3
export function PortfolioPage() {
  return (
    <>
      <PageHeader title={t('pages.portfolio.title')} />
      <EmptyState
        icon={Building2}
        title={t('pages.portfolio.emptyTitle')}
        text={t('pages.portfolio.emptyText')}
      />
    </>
  );
}
