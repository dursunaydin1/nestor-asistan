import { CircleAlert, MapPinOff } from 'lucide-react';
import { isRouteErrorResponse, Link, useRouteError } from 'react-router';
import { EmptyState } from '../components/EmptyState.tsx';
import { t } from '../i18n/index.ts';
import { paths } from './paths.ts';

const buttonClass =
  'inline-flex min-h-11 items-center rounded-xl bg-brand-800 px-5 font-semibold text-white hover:bg-brand-700';

export function RouteError() {
  const error = useRouteError();

  if (isRouteErrorResponse(error) && error.status === 404) {
    return (
      <EmptyState
        icon={MapPinOff}
        title={t('errors.notFound')}
        text={t('errors.notFoundText')}
        action={
          <Link to={paths.today} className={buttonClass}>
            {t('errors.goHome')}
          </Link>
        }
      />
    );
  }

  console.error(error);
  return (
    <EmptyState
      icon={CircleAlert}
      title={t('errors.generic')}
      text={t('errors.genericText')}
      action={
        <button type="button" onClick={() => window.location.reload()} className={buttonClass}>
          {t('errors.retry')}
        </button>
      }
    />
  );
}
