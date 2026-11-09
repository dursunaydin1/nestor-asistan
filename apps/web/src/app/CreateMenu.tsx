import {
  Building2,
  ClipboardList,
  MessageSquareText,
  Plus,
  UserPlus,
  X,
  type LucideIcon,
} from 'lucide-react';
import { useRef } from 'react';
import { t, type MessageKey } from '../i18n/index.ts';

type CreateAction = { id: string; label: MessageKey; icon: LucideIcon };

// PRD §12.1: Mülk / Kişi / Talep / Görüşme notu. Forms arrive in M3 and M4.
const actions: CreateAction[] = [
  { id: 'property', label: 'create.property', icon: Building2 },
  { id: 'person', label: 'create.person', icon: UserPlus },
  { id: 'request', label: 'create.request', icon: ClipboardList },
  { id: 'note', label: 'create.note', icon: MessageSquareText },
];

// Native <dialog> gives a focus trap, Escape to close and focus return for free (iOS 15.4+)
export function CreateMenu() {
  const dialogRef = useRef<HTMLDialogElement>(null);
  const close = () => dialogRef.current?.close();

  return (
    <>
      <button
        type="button"
        onClick={() => dialogRef.current?.showModal()}
        aria-label={t('create.open')}
        aria-haspopup="dialog"
        className="fixed bottom-[calc(var(--spacing-nav)+env(safe-area-inset-bottom)+1rem)] left-1/2 z-30 flex size-14 -translate-x-1/2 items-center justify-center rounded-full bg-accent-400 text-brand-900 shadow-lg shadow-brand-900/25 transition active:scale-95"
      >
        <Plus className="size-7" strokeWidth={2.5} aria-hidden="true" />
      </button>

      <dialog
        ref={dialogRef}
        aria-labelledby="create-menu-title"
        // A click on the backdrop lands on the <dialog> element itself
        onClick={(event) => event.target === event.currentTarget && close()}
        className="m-0 mt-auto w-full max-w-none bg-transparent p-0 backdrop:bg-brand-950/50"
      >
        <div className="mx-auto max-w-lg rounded-t-3xl bg-white px-4 pt-3 pb-[calc(env(safe-area-inset-bottom)+1.5rem)]">
          <div className="mx-auto mb-3 h-1.5 w-10 rounded-full bg-slate-300" aria-hidden="true" />
          <div className="mb-4 flex items-center justify-between">
            <h2 id="create-menu-title" className="text-lg font-semibold text-brand-900">
              {t('create.title')}
            </h2>
            <button
              type="button"
              onClick={close}
              aria-label={t('create.close')}
              className="flex size-11 items-center justify-center rounded-full text-slate-600 hover:bg-slate-100"
            >
              <X className="size-6" aria-hidden="true" />
            </button>
          </div>
          <ul className="grid grid-cols-2 gap-3">
            {actions.map(({ id, label, icon: Icon }) => (
              <li key={id}>
                <button
                  type="button"
                  onClick={close}
                  className="flex w-full flex-col items-center gap-2 rounded-2xl border border-slate-200 px-3 py-5 font-medium text-brand-900 transition hover:border-brand-200 hover:bg-brand-50 active:scale-[0.98]"
                >
                  <span className="flex size-12 items-center justify-center rounded-xl bg-brand-50 text-brand-700">
                    <Icon className="size-6" aria-hidden="true" />
                  </span>
                  {t(label)}
                </button>
              </li>
            ))}
          </ul>
        </div>
      </dialog>
    </>
  );
}
