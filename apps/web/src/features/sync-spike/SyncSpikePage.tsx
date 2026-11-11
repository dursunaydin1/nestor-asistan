import type { Session } from '@supabase/supabase-js';
import { useLiveQuery } from 'dexie-react-hooks';
import { useEffect, useState, type FormEvent } from 'react';
import { PageHeader } from '../../components/PageHeader.tsx';
import { supabase, supabaseConfigured } from '../../data/supabase.ts';
import { t } from '../../i18n/index.ts';
import { clearLocal, db, saveLocal } from './db.ts';
import type { LocalItem } from './merge.ts';
import { syncNow, type SyncReport } from './sync.ts';

const inputClass =
  'min-h-11 w-full rounded-xl border border-slate-300 bg-white px-3 text-brand-900 focus:border-brand-500';
const primaryButton =
  'min-h-11 shrink-0 rounded-xl bg-brand-800 px-4 font-semibold text-white hover:bg-brand-700 disabled:opacity-50';
const secondaryButton =
  'min-h-11 shrink-0 rounded-xl border border-slate-300 px-3 font-semibold text-brand-900';

export function SyncSpikePage() {
  const [session, setSession] = useState<Session | null | undefined>(undefined);

  useEffect(() => {
    if (!supabaseConfigured) return;
    void supabase.auth.getSession().then(({ data }) => setSession(data.session));
    const { data } = supabase.auth.onAuthStateChange((_event, next) => setSession(next));
    return () => data.subscription.unsubscribe();
  }, []);

  return (
    <>
      <PageHeader title={t('syncSpike.title')} />
      <p className="px-4 text-sm text-slate-600">{t('syncSpike.intro')}</p>
      {!supabaseConfigured ? (
        <p className="m-4 rounded-xl bg-red-50 p-3 text-sm text-red-800">
          {t('syncSpike.notConfigured')}
        </p>
      ) : session === null ? (
        <SignInForm />
      ) : session ? (
        <SyncPanel email={session.user.email ?? ''} />
      ) : null}
    </>
  );
}

function SignInForm() {
  const [failed, setFailed] = useState(false);
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    setBusy(true);
    const { error } = await supabase.auth.signInWithPassword({
      email: String(form.get('email')),
      password: String(form.get('password')),
    });
    setBusy(false);
    setFailed(Boolean(error));
  }

  return (
    <form onSubmit={(event) => void submit(event)} className="mt-4 space-y-3 px-4">
      <label className="block text-sm font-medium text-brand-900">
        {t('syncSpike.email')}
        <input name="email" type="email" autoComplete="username" required className={inputClass} />
      </label>
      <label className="block text-sm font-medium text-brand-900">
        {t('syncSpike.password')}
        <input
          name="password"
          type="password"
          autoComplete="current-password"
          required
          className={inputClass}
        />
      </label>
      {failed && <p className="text-sm text-red-800">{t('syncSpike.signInError')}</p>}
      <button type="submit" disabled={busy} className={primaryButton}>
        {t('syncSpike.signIn')}
      </button>
    </form>
  );
}

function useOnline(): boolean {
  const [online, setOnline] = useState(navigator.onLine);
  useEffect(() => {
    const update = () => setOnline(navigator.onLine);
    window.addEventListener('online', update);
    window.addEventListener('offline', update);
    return () => {
      window.removeEventListener('online', update);
      window.removeEventListener('offline', update);
    };
  }, []);
  return online;
}

function SyncPanel({ email }: { email: string }) {
  const online = useOnline();
  const [report, setReport] = useState<SyncReport | null>(null);
  const [title, setTitle] = useState('');
  const items = useLiveQuery(() => db.items.orderBy('updatedAt').reverse().toArray(), []);
  const outbox = useLiveQuery(() => db.outbox.toArray(), []);

  // Triggers from tech-architecture §10.3: coming online, returning to the foreground, 60 s timer
  useEffect(() => {
    const run = () => void syncNow().then(setReport);
    const onVisible = () => document.visibilityState === 'visible' && run();
    run();
    window.addEventListener('online', run);
    document.addEventListener('visibilitychange', onVisible);
    const timer = window.setInterval(() => document.visibilityState === 'visible' && run(), 60_000);
    return () => {
      window.removeEventListener('online', run);
      document.removeEventListener('visibilitychange', onVisible);
      window.clearInterval(timer);
    };
  }, []);

  async function add(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const value = title.trim();
    if (!value) return;
    setTitle('');
    await saveLocal(crypto.randomUUID(), value, false);
    void syncNow().then(setReport);
  }

  async function signOut() {
    await supabase.auth.signOut();
    await clearLocal();
  }

  const visible = (items ?? []).filter((item) => !item.deletedAt);
  const waiting = (outbox ?? []).filter((entry) => entry.status !== 'attention').length;

  return (
    <div className="mt-4 space-y-4 px-4">
      <div className="flex flex-wrap items-center gap-2 text-sm">
        <span
          className={`rounded-full px-2.5 py-0.5 font-semibold ${online ? 'bg-emerald-50 text-emerald-800' : 'bg-amber-50 text-amber-900'}`}
        >
          {online ? t('syncSpike.online') : t('syncSpike.offline')}
        </span>
        <span className="text-slate-600">
          {t('syncSpike.outbox')}: {waiting}
        </span>
        <span className="text-slate-600">
          {t('syncSpike.lastSync')}:{' '}
          {report ? new Date(report.at).toLocaleTimeString('tr-TR') : t('syncSpike.never')}
        </span>
      </div>

      <form onSubmit={(event) => void add(event)} className="flex gap-2">
        <input
          value={title}
          onChange={(event) => setTitle(event.target.value)}
          placeholder={t('syncSpike.newItem')}
          aria-label={t('syncSpike.newItem')}
          maxLength={200}
          className={inputClass}
        />
        <button type="submit" className={primaryButton}>
          {t('syncSpike.add')}
        </button>
      </form>

      <ul className="space-y-2">
        {visible.map((item) => (
          <ItemRow
            key={item.id}
            item={item}
            entryStatus={outbox?.find((entry) => entry.itemId === item.id)?.status}
            onChanged={() => void syncNow().then(setReport)}
          />
        ))}
        {items && visible.length === 0 && (
          <li className="text-sm text-slate-600">{t('syncSpike.empty')}</li>
        )}
      </ul>

      <div className="flex flex-wrap gap-2">
        <button
          type="button"
          onClick={() => void syncNow().then(setReport)}
          className={primaryButton}
        >
          {t('syncSpike.syncNow')}
        </button>
        <button type="button" onClick={() => void signOut()} className={secondaryButton}>
          {t('syncSpike.signOut')} ({email})
        </button>
      </div>
    </div>
  );
}

function ItemRow({
  item,
  entryStatus,
  onChanged,
}: {
  item: LocalItem;
  entryStatus: string | undefined;
  onChanged: () => void;
}) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(item.title);

  const state =
    entryStatus === 'attention'
      ? 'attention'
      : entryStatus
        ? 'pending'
        : item.overwritten
          ? 'overwritten'
          : 'synced';
  const stateStyle = {
    attention: 'text-red-800',
    pending: 'text-amber-900',
    overwritten: 'text-amber-900',
    synced: 'text-emerald-800',
  }[state];

  async function save(deleted: boolean) {
    const value = deleted ? item.title : draft.trim();
    if (!value) return;
    setEditing(false);
    await saveLocal(item.id, value, deleted);
    onChanged();
  }

  return (
    <li className="rounded-xl border border-slate-200 bg-white p-3">
      {editing ? (
        <div className="flex gap-2">
          <input
            value={draft}
            onChange={(event) => setDraft(event.target.value)}
            aria-label={t('syncSpike.edit')}
            maxLength={200}
            className={inputClass}
          />
          <button type="button" onClick={() => void save(false)} className={primaryButton}>
            {t('syncSpike.save')}
          </button>
          <button type="button" onClick={() => setEditing(false)} className={secondaryButton}>
            {t('syncSpike.cancel')}
          </button>
        </div>
      ) : (
        <div className="flex items-start justify-between gap-2">
          <div className="min-w-0">
            <p className="font-medium break-words text-brand-900">{item.title}</p>
            <p className={`text-xs ${stateStyle}`}>
              {t(`syncSpike.state.${state}`)} · {t('syncSpike.version')} {item.version}
            </p>
          </div>
          <div className="flex shrink-0 gap-1">
            <button
              type="button"
              onClick={() => {
                setDraft(item.title);
                setEditing(true);
              }}
              className={secondaryButton}
            >
              {t('syncSpike.edit')}
            </button>
            <button type="button" onClick={() => void save(true)} className={secondaryButton}>
              {t('syncSpike.delete')}
            </button>
          </div>
        </div>
      )}
    </li>
  );
}
