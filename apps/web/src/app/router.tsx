import { createBrowserRouter, Navigate } from 'react-router';
import { AppShell } from './AppShell.tsx';
import { paths } from './paths.ts';
import { RouteError } from './RouteError.tsx';

// Each tab is lazy-loaded so the initial bundle stays within the PRD §12 budget (≤ 250 KB gzip)
export const router = createBrowserRouter([
  {
    element: <AppShell />,
    errorElement: <RouteError />,
    hydrateFallbackElement: null,
    children: [
      {
        errorElement: <RouteError />,
        children: [
          { index: true, element: <Navigate to={paths.today} replace /> },
          {
            path: paths.today,
            lazy: async () => ({
              Component: (await import('../features/today/TodayPage.tsx')).TodayPage,
            }),
          },
          {
            path: paths.query,
            lazy: async () => ({
              Component: (await import('../features/query/QueryPage.tsx')).QueryPage,
            }),
          },
          {
            path: paths.portfolio,
            lazy: async () => ({
              Component: (await import('../features/properties/PortfolioPage.tsx')).PortfolioPage,
            }),
          },
          {
            path: paths.customers,
            lazy: async () => ({
              Component: (await import('../features/persons/CustomersPage.tsx')).CustomersPage,
            }),
          },
          {
            path: paths.more,
            lazy: async () => ({
              Component: (await import('../features/more/MorePage.tsx')).MorePage,
            }),
          },
          {
            path: paths.diagnostics,
            lazy: async () => ({
              Component: (await import('../features/diagnostics/DiagnosticsPage.tsx'))
                .DiagnosticsPage,
            }),
          },
          {
            path: paths.syncSpike,
            lazy: async () => ({
              Component: (await import('../features/sync-spike/SyncSpikePage.tsx')).SyncSpikePage,
            }),
          },
          {
            path: '*',
            element: <RouteError />,
            loader: () => {
              throw new Response(null, { status: 404 });
            },
          },
        ],
      },
    ],
  },
]);
