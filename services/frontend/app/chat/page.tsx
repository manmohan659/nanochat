'use client';

import { Suspense } from 'react';
import { useAuth } from '@/hooks/useAuth';
import Sidebar from '@/components/chat/Sidebar';
import ChatWindow from '@/components/chat/ChatWindow';
import { redirect } from 'next/navigation';

function ChatContent() {
  const { authenticated, loading } = useAuth();

  if (loading) {
    return <div className="flex h-dvh items-center justify-center bg-white dark:bg-ink text-gray-700 dark:text-ink-text-soft">Loading…</div>;
  }
  if (!authenticated) {
    redirect('/login');
    return null;
  }

  return (
    <main className="flex h-dvh overflow-hidden bg-white dark:bg-ink">
      <Sidebar />
      <ChatWindow />
    </main>
  );
}

export default function ChatPage() {
  return (
    <Suspense fallback={<div className="flex h-dvh items-center justify-center bg-white dark:bg-ink text-gray-700 dark:text-ink-text-soft">Loading…</div>}>
      <ChatContent />
    </Suspense>
  );
}
