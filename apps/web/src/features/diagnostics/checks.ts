// Device capability probes for M0 step 8 (ADR-0002): installability, storage, IndexedDB, push.
// Each probe resolves to a result and never throws, so one failure cannot hide the others.
import { t } from '../../i18n/index.ts';

export type CheckId =
  | 'standalone'
  | 'serviceWorker'
  | 'persist'
  | 'quota'
  | 'indexedDb'
  | 'notification'
  | 'push'
  | 'device';

export type CheckStatus = 'ok' | 'fail' | 'info';
export type CheckResult = { id: CheckId; status: CheckStatus; detail: string };

function errorResult(id: CheckId, error: unknown): CheckResult {
  const message = error instanceof Error ? `${error.name}: ${error.message}` : String(error);
  return { id, status: 'fail', detail: `${t('diagnostics.detail.error')}: ${message}` };
}

function formatBytes(bytes: number): string {
  const mb = bytes / 1024 / 1024;
  return mb >= 1024
    ? `${(mb / 1024).toLocaleString('tr-TR', { maximumFractionDigits: 1 })} GB`
    : `${mb.toLocaleString('tr-TR', { maximumFractionDigits: 0 })} MB`;
}

export function checkStandalone(): CheckResult {
  const iosStandalone = (navigator as Navigator & { standalone?: boolean }).standalone === true;
  const standalone = window.matchMedia('(display-mode: standalone)').matches || iosStandalone;
  return {
    id: 'standalone',
    status: standalone ? 'ok' : 'info',
    detail: t(standalone ? 'diagnostics.detail.yes' : 'diagnostics.detail.no'),
  };
}

export async function checkServiceWorker(): Promise<CheckResult> {
  const id = 'serviceWorker';
  if (!('serviceWorker' in navigator)) {
    return { id, status: 'fail', detail: t('diagnostics.detail.unsupported') };
  }
  try {
    const registration = await navigator.serviceWorker.getRegistration();
    return registration?.active
      ? { id, status: 'ok', detail: t('diagnostics.detail.active') }
      : { id, status: 'fail', detail: t('diagnostics.detail.notRegistered') };
  } catch (error) {
    return errorResult(id, error);
  }
}

export async function checkPersist(): Promise<CheckResult> {
  const id = 'persist';
  if (!navigator.storage?.persist) {
    return { id, status: 'fail', detail: t('diagnostics.detail.unsupported') };
  }
  try {
    const persisted = (await navigator.storage.persisted()) || (await navigator.storage.persist());
    return {
      id,
      status: persisted ? 'ok' : 'fail',
      detail: t(persisted ? 'diagnostics.detail.granted' : 'diagnostics.detail.denied'),
    };
  } catch (error) {
    return errorResult(id, error);
  }
}

export async function checkQuota(): Promise<CheckResult> {
  const id = 'quota';
  if (!navigator.storage?.estimate) {
    return { id, status: 'fail', detail: t('diagnostics.detail.unsupported') };
  }
  try {
    const { usage = 0, quota = 0 } = await navigator.storage.estimate();
    return { id, status: 'info', detail: `${formatBytes(usage)} / ${formatBytes(quota)}` };
  } catch (error) {
    return errorResult(id, error);
  }
}

function request<T>(req: IDBRequest<T>): Promise<T> {
  return new Promise((resolve, reject) => {
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error ?? new Error('IndexedDB request failed'));
  });
}

// Writes and reads back one record in a throwaway database, then deletes it
export async function checkIndexedDb(): Promise<CheckResult> {
  const id = 'indexedDb';
  if (!('indexedDB' in window)) {
    return { id, status: 'fail', detail: t('diagnostics.detail.unsupported') };
  }
  const name = 'app-diagnostics';
  try {
    const open = indexedDB.open(name, 1);
    open.onupgradeneeded = () => open.result.createObjectStore('probe', { keyPath: 'id' });
    const db = await request(open);
    const value = `probe-${Date.now()}`;
    await request(db.transaction('probe', 'readwrite').objectStore('probe').put({ id: 1, value }));
    const stored = await request<{ value: string } | undefined>(
      db.transaction('probe').objectStore('probe').get(1),
    );
    db.close();
    await request(indexedDB.deleteDatabase(name));
    return stored?.value === value
      ? { id, status: 'ok', detail: t('diagnostics.detail.readWriteOk') }
      : { id, status: 'fail', detail: t('diagnostics.detail.error') };
  } catch (error) {
    return errorResult(id, error);
  }
}

export function checkNotificationPermission(): CheckResult {
  const id = 'notification';
  if (!('Notification' in window)) {
    return { id, status: 'fail', detail: t('diagnostics.detail.unsupported') };
  }
  const permission = Notification.permission;
  return {
    id,
    status: permission === 'granted' ? 'ok' : permission === 'denied' ? 'fail' : 'info',
    detail: t(`diagnostics.detail.${permission}`),
  };
}

// Subscribes with a throwaway key generated in the browser, reports the push service host,
// then unsubscribes. No key leaves the device and nothing is stored on a server.
export async function checkPushSubscription(): Promise<CheckResult> {
  const id = 'push';
  if (!('serviceWorker' in navigator) || !('PushManager' in window)) {
    return { id, status: 'fail', detail: t('diagnostics.detail.unsupported') };
  }
  try {
    const registration = await navigator.serviceWorker.ready;
    await (await registration.pushManager.getSubscription())?.unsubscribe();
    const keys = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, [
      'sign',
    ]);
    const applicationServerKey = await crypto.subtle.exportKey('raw', keys.publicKey);
    const subscription = await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey,
    });
    const host = new URL(subscription.endpoint).host;
    await subscription.unsubscribe();
    return { id, status: 'ok', detail: host };
  } catch (error) {
    return errorResult(id, error);
  }
}

export function deviceInfo(): CheckResult {
  return { id: 'device', status: 'info', detail: navigator.userAgent };
}

export async function runAutomaticChecks(): Promise<CheckResult[]> {
  return [
    checkStandalone(),
    await checkServiceWorker(),
    await checkPersist(),
    await checkQuota(),
    await checkIndexedDb(),
    checkNotificationPermission(),
    { id: 'push', status: 'info', detail: t('diagnostics.detail.afterPermission') },
    deviceInfo(),
  ];
}
