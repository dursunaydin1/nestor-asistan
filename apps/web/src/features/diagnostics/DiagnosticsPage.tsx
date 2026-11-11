import { useCallback, useEffect, useState } from 'react';
import { PageHeader } from '../../components/PageHeader.tsx';
import { t } from '../../i18n/index.ts';
import {
  checkNotificationPermission,
  checkPushSubscription,
  runAutomaticChecks,
  type CheckResult,
  type CheckStatus,
} from './checks.ts';

const statusStyle: Record<CheckStatus, string> = {
  ok: 'bg-emerald-50 text-emerald-800',
  fail: 'bg-red-50 text-red-800',
  info: 'bg-slate-100 text-slate-700',
};

function replace(results: CheckResult[], next: CheckResult): CheckResult[] {
  return results.map((result) => (result.id === next.id ? next : result));
}

export function DiagnosticsPage() {
  const [results, setResults] = useState<CheckResult[] | null>(null);
  const [copied, setCopied] = useState(false);

  const run = useCallback(async () => {
    setResults(null);
    setResults(await runAutomaticChecks());
  }, []);

  useEffect(() => {
    void run();
  }, [run]);

  async function testNotifications() {
    if (!('Notification' in window)) return;
    const permission = await Notification.requestPermission();
    setResults((current) => current && replace(current, checkNotificationPermission()));
    if (permission !== 'granted') return;
    const registration = await navigator.serviceWorker.ready;
    await registration.showNotification(t('diagnostics.testNotificationTitle'), {
      body: t('diagnostics.testNotificationBody'),
      icon: '/pwa-192x192.png',
    });
    const push = await checkPushSubscription();
    setResults((current) => current && replace(current, push));
  }

  async function copy() {
    if (!results) return;
    const text = results
      .map(
        (r) =>
          `${t(`diagnostics.checks.${r.id}`)}: ${t(`diagnostics.status.${r.status}`)} — ${r.detail}`,
      )
      .join('\n');
    await navigator.clipboard.writeText(text);
    setCopied(true);
  }

  const buttonClass =
    'min-h-11 rounded-xl px-4 font-semibold disabled:opacity-50 bg-brand-800 text-white hover:bg-brand-700';

  return (
    <>
      <PageHeader title={t('diagnostics.title')} />
      <p className="px-4 text-sm text-slate-600">{t('diagnostics.intro')}</p>

      <ul className="mt-4 space-y-2 px-4" aria-live="polite">
        {(results ?? []).map((result) => (
          <li key={result.id} className="rounded-xl border border-slate-200 bg-white p-3">
            <div className="flex items-center justify-between gap-3">
              <span className="font-medium text-brand-900">
                {t(`diagnostics.checks.${result.id}`)}
              </span>
              <span
                data-testid={`status-${result.id}`}
                className={`shrink-0 rounded-full px-2.5 py-0.5 text-xs font-semibold ${statusStyle[result.status]}`}
              >
                {t(`diagnostics.status.${result.status}`)}
              </span>
            </div>
            <p className="mt-1 text-sm break-words text-slate-600">{result.detail}</p>
          </li>
        ))}
        {!results && <li className="text-sm text-slate-600">{t('diagnostics.status.pending')}</li>}
      </ul>

      <div className="mt-4 flex flex-wrap gap-2 px-4">
        <button type="button" onClick={() => void testNotifications()} className={buttonClass}>
          {t('diagnostics.notifyButton')}
        </button>
        <button
          type="button"
          onClick={() => void copy()}
          disabled={!results}
          className={buttonClass}
        >
          {copied ? t('diagnostics.copied') : t('diagnostics.copy')}
        </button>
        <button
          type="button"
          onClick={() => void run()}
          className="min-h-11 rounded-xl border border-slate-300 px-4 font-semibold text-brand-900"
        >
          {t('diagnostics.rerun')}
        </button>
      </div>
    </>
  );
}
