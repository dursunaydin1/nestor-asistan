import { Settings } from 'lucide-react';
import { EmptyState } from '../../components/EmptyState.tsx';
import { PageHeader } from '../../components/PageHeader.tsx';
import { t } from '../../i18n/index.ts';

// Settings, office, staff, import/export and admin entries arrive in M2, M7 and M9
export function MorePage() {
  return (
    <>
      <PageHeader title={t('pages.more.title')} />
      <EmptyState
        icon={Settings}
        title={t('pages.more.emptyTitle')}
        text={t('pages.more.emptyText')}
      />
    </>
  );
}
