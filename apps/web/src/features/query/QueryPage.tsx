import { Search } from 'lucide-react';
import { EmptyState } from '../../components/EmptyState.tsx';
import { PageHeader } from '../../components/PageHeader.tsx';
import { t } from '../../i18n/index.ts';

// Filter bar, results and "save as request" arrive in M4
export function QueryPage() {
  return (
    <>
      <PageHeader title={t('pages.query.title')} />
      <EmptyState
        icon={Search}
        title={t('pages.query.emptyTitle')}
        text={t('pages.query.emptyText')}
      />
    </>
  );
}
