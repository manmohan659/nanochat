'use client';

import { Suspense, useEffect, useState } from 'react';
import { useRouter } from 'next/navigation';
import Link from 'next/link';
import { useAuth } from '@/hooks/useAuth';
import { authHeaders } from '@/lib/auth-client';

interface AdminUser {
  id: string;
  email: string;
  name: string | null;
  provider: string;
  created_at: string | null;
  last_login_at: string | null;
  conversation_count: number;
  message_count: number;
}

interface AdminPayload {
  items: AdminUser[];
  totals: { users: number; conversations: number; messages: number };
}

function fmt(dt: string | null): string {
  if (!dt) return '—';
  const d = new Date(dt);
  return d.toLocaleString(undefined, {
    year: 'numeric',
    month: 'short',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  });
}

function DashboardContent() {
  const { authenticated, loading, user } = useAuth();
  const router = useRouter();
  const [data, setData] = useState<AdminPayload | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [fetching, setFetching] = useState(true);

  useEffect(() => {
    if (loading) return;
    if (!authenticated) {
      router.push('/login');
      return;
    }
    let cancelled = false;
    (async () => {
      setFetching(true);
      try {
        const res = await fetch('/api/admin/users', {
          headers: { ...authHeaders() },
        });
        if (res.status === 403) {
          if (!cancelled) setError('forbidden');
          return;
        }
        if (!res.ok) {
          if (!cancelled) setError(`HTTP ${res.status}`);
          return;
        }
        const payload: AdminPayload = await res.json();
        if (!cancelled) setData(payload);
      } catch (e) {
        if (!cancelled) setError((e as Error).message);
      } finally {
        if (!cancelled) setFetching(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [authenticated, loading, router]);

  if (loading || (fetching && !data && !error)) {
    return (
      <div className="flex h-dvh items-center justify-center bg-white dark:bg-ink text-gray-700 dark:text-ink-text-soft">
        Loading…
      </div>
    );
  }

  if (error === 'forbidden') {
    return (
      <div className="flex h-dvh flex-col items-center justify-center gap-4 bg-white dark:bg-ink text-gray-700 dark:text-ink-text-soft px-6 text-center">
        <div className="text-3xl opacity-30">🔒</div>
        <h1 className="text-xl font-semibold text-gray-900 dark:text-ink-text">Admin only</h1>
        <p className="text-sm">
          Signed in as <span className="font-medium">{user?.email ?? 'unknown'}</span>. This dashboard is restricted.
        </p>
        <Link
          href="/chat"
          className="inline-flex items-center gap-2 px-5 py-2 rounded-full bg-gray-900 dark:bg-ink-text text-white dark:text-ink text-sm font-medium hover:-translate-y-px transition-all"
        >
          Back to chat
        </Link>
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex h-dvh items-center justify-center bg-white dark:bg-ink text-chutney-red px-6 text-center">
        Failed to load dashboard: {error}
      </div>
    );
  }

  return (
    <main className="min-h-dvh bg-white dark:bg-ink text-gray-900 dark:text-ink-text">
      <header className="border-b border-cream-border dark:border-ink-border px-4 md:px-8 py-4 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <Link href="/chat" className="text-sm text-gray-500 dark:text-ink-text-soft hover:text-saffron transition-colors">
            ← Back to chat
          </Link>
          <span className="text-gray-300 dark:text-ink-border">/</span>
          <h1 className="font-display font-semibold text-lg tracking-tight">Admin dashboard</h1>
        </div>
        <span className="text-xs text-gray-400 dark:text-ink-text-soft">{user?.email}</span>
      </header>

      <div className="px-4 md:px-8 py-6 max-w-6xl mx-auto">
        {data && (
          <>
            <section className="grid grid-cols-3 gap-3 md:gap-4 mb-6">
              <Stat label="Users" value={data.totals.users} />
              <Stat label="Conversations" value={data.totals.conversations} />
              <Stat label="Messages" value={data.totals.messages} />
            </section>

            <section className="rounded-xl border border-cream-border dark:border-ink-border overflow-hidden bg-white dark:bg-ink-soft">
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="bg-cream-light dark:bg-ink-elev text-left text-[11px] uppercase tracking-wider text-gray-500 dark:text-ink-text-soft">
                    <tr>
                      <th className="px-3 py-2 font-medium">Email</th>
                      <th className="px-3 py-2 font-medium">Name</th>
                      <th className="px-3 py-2 font-medium">Provider</th>
                      <th className="px-3 py-2 font-medium">Joined</th>
                      <th className="px-3 py-2 font-medium">Last login</th>
                      <th className="px-3 py-2 font-medium text-right">Conversations</th>
                      <th className="px-3 py-2 font-medium text-right">Messages</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-cream-border dark:divide-ink-border">
                    {data.items.length === 0 ? (
                      <tr>
                        <td colSpan={7} className="px-3 py-8 text-center text-gray-400 dark:text-ink-text-soft">
                          No users yet.
                        </td>
                      </tr>
                    ) : (
                      data.items.map((u) => (
                        <tr key={u.id} className="hover:bg-cream/50 dark:hover:bg-ink-elev/50">
                          <td className="px-3 py-2 font-medium text-gray-800 dark:text-ink-text whitespace-nowrap">{u.email}</td>
                          <td className="px-3 py-2 text-gray-600 dark:text-ink-text-soft whitespace-nowrap">{u.name ?? '—'}</td>
                          <td className="px-3 py-2 text-gray-600 dark:text-ink-text-soft">
                            <span className="inline-flex items-center px-2 py-0.5 rounded-full text-[11px] font-medium bg-cream-light dark:bg-ink-elev">
                              {u.provider}
                            </span>
                          </td>
                          <td className="px-3 py-2 text-gray-600 dark:text-ink-text-soft whitespace-nowrap">{fmt(u.created_at)}</td>
                          <td className="px-3 py-2 text-gray-600 dark:text-ink-text-soft whitespace-nowrap">{fmt(u.last_login_at)}</td>
                          <td className="px-3 py-2 text-right tabular-nums">{u.conversation_count}</td>
                          <td className="px-3 py-2 text-right tabular-nums">{u.message_count}</td>
                        </tr>
                      ))
                    )}
                  </tbody>
                </table>
              </div>
            </section>
          </>
        )}
      </div>
    </main>
  );
}

function Stat({ label, value }: { label: string; value: number }) {
  return (
    <div className="rounded-xl border border-cream-border dark:border-ink-border bg-white dark:bg-ink-soft px-4 py-3">
      <div className="text-[11px] uppercase tracking-wider text-gray-400 dark:text-ink-text-soft">{label}</div>
      <div className="mt-1 text-2xl font-semibold tabular-nums text-gray-900 dark:text-ink-text">
        {value.toLocaleString()}
      </div>
    </div>
  );
}

export default function DashboardPage() {
  return (
    <Suspense
      fallback={
        <div className="flex h-dvh items-center justify-center bg-white dark:bg-ink text-gray-700 dark:text-ink-text-soft">
          Loading…
        </div>
      }
    >
      <DashboardContent />
    </Suspense>
  );
}
