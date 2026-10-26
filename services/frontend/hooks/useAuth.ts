"use client";
import { useEffect, useState } from 'react';
import { sessionJSON } from '@/lib/session-request';
import { useRouter } from 'next/navigation';
import { getToken, setToken, clearToken, getUser, refreshAccessToken, logoutSession, authGeneration, type TokenUser } from '@/lib/auth-client';

let initializing: Promise<boolean> | null = null;
async function initialize(): Promise<boolean> {
  const code = new URLSearchParams(window.location.search).get('code');
  if (getToken() && !code) return true;
  if (!initializing) initializing = (async () => {
    const started = authGeneration();
    // Strip the short-lived code before fetching or rendering application content.
    if (code) window.history.replaceState(null, '', '/chat');
    if (!code) {
      const token = await refreshAccessToken();
      if (!token) { clearToken(); return false; }
      if (started !== authGeneration()) return false;
      setToken(token); return true;
    }
    const data = await sessionJSON('/api/auth/exchange', { code });
    if (!data) { clearToken(); return false; }
    if (typeof data.access_token !== 'string') return false;
    if (started !== authGeneration()) return false;
    setToken(data.access_token);
    return true;
  })().finally(() => { initializing = null; });
  return initializing;
}

export function useAuth() {
  const [error, setError] = useState(false);
  const [attempt, setAttempt] = useState(0);
  const [authenticated, setAuthenticated] = useState(false);
  const [loading, setLoading] = useState(true);
  const [user, setUser] = useState<TokenUser | null>(null);
  const router = useRouter();
  useEffect(() => {
    let active = true;
    setLoading(true); setError(false);
    initialize().then(ok => { if (active) { setAuthenticated(ok); setUser(getUser()); setLoading(false); } }).catch(() => { if (active) { setError(true); setLoading(false); } });
    return () => { active = false; };
  }, [attempt]);
  const logout = async () => {
    await logoutSession().catch(() => undefined);
    clearToken(); setAuthenticated(false); setUser(null); router.push('/');
  };
  return { authenticated, loading, user, logout, error, retry: () => setAttempt(value => value + 1) };
}
