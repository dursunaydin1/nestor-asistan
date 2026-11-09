import type { LucideIcon } from 'lucide-react';
import type { ReactNode } from 'react';

type EmptyStateProps = {
  icon: LucideIcon;
  title: string;
  text: string;
  action?: ReactNode;
};

export function EmptyState({ icon: Icon, title, text, action }: EmptyStateProps) {
  return (
    <div className="flex flex-col items-center px-6 py-16 text-center">
      <div className="mb-5 flex size-16 items-center justify-center rounded-2xl bg-brand-50 text-brand-700">
        <Icon className="size-8" strokeWidth={1.75} aria-hidden="true" />
      </div>
      <h2 className="text-lg font-semibold text-brand-900">{title}</h2>
      <p className="mt-2 max-w-xs text-sm leading-relaxed text-slate-600">{text}</p>
      {action && <div className="mt-6">{action}</div>}
    </div>
  );
}
