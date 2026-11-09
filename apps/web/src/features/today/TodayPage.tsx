import { CalendarCheck } from 'lucide-react';
import { EmptyState } from '../../components/EmptyState.tsx';
import { PageHeader } from '../../components/PageHeader.tsx';
import { t } from '../../i18n/index.ts';

// Reminders, new matches, overdue items and stale listings arrive in M6
export function TodayPage() {
  return (
    <>
      <PageHeader title={t('pages.today.title')} />
      <EmptyState
        icon={CalendarCheck}
        title={t('pages.today.emptyTitle')}
        text={t('pages.today.emptyText')}
      />
    </>
  );
}
