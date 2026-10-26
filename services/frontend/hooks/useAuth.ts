"use client";
import { useEffect, useState } from 'react';
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
    const response = await fetch('/api/auth/exchange', { method: 'POST', credentials: 'same-origin', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(code ? { code } : {}), cache: 'no-store' });
    if (!response.ok) { clearToken(); return false; }
    const data = await response.json();
    if (typeof data.access_token !== 'string') return false;
    if (started !== authGeneration()) return false;
    setToken(data.access_token);
    return true;
  })().catch(() => false).finally(() => { initializing = null; });
  return initializing;
}

export function useAuth() {
  const [authenticated, setAuthenticated] = useState(false);
  const [loading, setLoading] = useState(true);
  const [user, setUser] = useState<TokenUser | null>(null);
  const router = useRouter();
  useEffect(() => {
    let active = true;
    initialize().then(ok => { if (active) { setAuthenticated(ok); setUser(getUser()); setLoading(false); } });
    return () => { active = false; };
  }, []);
  const logout = async () => {
    await logoutSession().catch(() => undefined);
    clearToken(); setAuthenticated(false); setUser(null); router.push('/');
  };
  return { authenticated, loading, user, logout };
}
