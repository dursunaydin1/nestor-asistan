type PageHeaderProps = {
  title: string;
};

export function PageHeader({ title }: PageHeaderProps) {
  return (
    <h1 className="px-4 pt-5 pb-2 text-2xl font-bold tracking-tight text-brand-900">{title}</h1>
  );
}
