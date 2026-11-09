import { Users } from 'lucide-react';
import { EmptyState } from '../../components/EmptyState.tsx';
import { PageHeader } from '../../components/PageHeader.tsx';
import { t } from '../../i18n/index.ts';

// Customer list, status filters and search arrive in M3
export function CustomersPage() {
  return (
    <>
      <PageHeader title={t('pages.customers.title')} />
      <EmptyState
        icon={Users}
        title={t('pages.customers.emptyTitle')}
        text={t('pages.customers.emptyText')}
      />
    </>
  );
}
