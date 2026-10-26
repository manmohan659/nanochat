let generation = 0;
const sessionChannel = typeof window !== 'undefined' && typeof BroadcastChannel !== 'undefined' ? new BroadcastChannel('samosachaat-session') : null;
if (sessionChannel) sessionChannel.onmessage = event => {
  if (event.data === 'logout') {
    clearToken();
    if (['/chat', '/dashboard'].includes(window.location.pathname)) window.location.assign('/login');
  }
};
export function authGeneration(): number { return generation; }
let memoryToken: string | null = null;
let memoryUser: TokenUser | null = null;
let refreshTimer: ReturnType<typeof setTimeout> | null = null;
const SESSION_TRACE_KEY = 'samosachaat_session_trace_id';

export interface TokenUser {
  name: string;
  email: string;
}

export function getToken(): string | null {
  if (typeof window === 'undefined') return null;
  return memoryToken;
}

export function setToken(token: string): void {
  memoryToken = token;
  // Remove legacy persistent bearer storage on upgrade.
  try { localStorage.removeItem('samosachaat_access_token'); localStorage.removeItem('samosachaat_user'); } catch { /* legacy storage may be blocked; tokens now live only in memory */ }
  if (refreshTimer) clearTimeout(refreshTimer);
  // Decode JWT payload to persist basic user info
  try {
    const payload = JSON.parse(atob(token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')));
    const user: TokenUser = {
      name: payload.name || payload.email || 'User',
      email: payload.email || '',
    };
    memoryUser = user;
    const delay = Math.max(1000, (Number(payload.exp) * 1000 - Date.now()) - 60000);
    if (Number.isFinite(delay)) refreshTimer = setTimeout(async () => {
      const started = generation;
      try {
        const nextToken = await refreshAccessToken();
        if (started !== generation) return;
        if (!nextToken) { clearToken(); window.location.assign('/login'); return; }
        setToken(nextToken);
      } catch { if (started === generation) { clearToken(); window.location.assign('/login'); } }
    }, delay);
  } catch {
    /* malformed JWT — ignore */
  }
}

export function clearToken(): void {
  generation += 1;
  memoryToken = null; memoryUser = null;
  if (refreshTimer) clearTimeout(refreshTimer);
  refreshTimer = null;
  try { localStorage.removeItem('samosachaat_access_token'); localStorage.removeItem('samosachaat_user'); } catch { /* legacy storage may be blocked; tokens now live only in memory */ }
}

export function isAuthenticated(): boolean {
  return !!getToken();
}

export function getUser(): TokenUser | null {
  if (typeof window === 'undefined') return null;
  return memoryUser;
}

function newSessionTraceId(): string {
  const random = globalThis.crypto?.randomUUID?.();
  if (random) return random.replace(/-/g, '');
  return `${Date.now().toString(36)}${Math.random().toString(36).slice(2)}`;
}

export function getSessionTraceId(): string | null {
  if (typeof window === 'undefined') return null;
  try {
    let sessionTraceId = window.sessionStorage.getItem(SESSION_TRACE_KEY);
    if (!sessionTraceId) {
      sessionTraceId = newSessionTraceId();
      window.sessionStorage.setItem(SESSION_TRACE_KEY, sessionTraceId);
    }
    return sessionTraceId;
  } catch {
    return null;
  }
}

export function sessionHeaders(): Record<string, string> {
  const sessionTraceId = getSessionTraceId();
  return sessionTraceId ? { 'x-session-trace-id': sessionTraceId } : {};
}

export function authHeaders(): Record<string, string> {
  const headers = sessionHeaders();
  const token = getToken();
  if (token) headers.Authorization = `Bearer ${token}`;
  return headers;
}

export async function refreshAccessToken(): Promise<string | null> {
  const refresh = async () => {
    const response = await fetch('/api/auth/refresh', { method: 'POST', credentials: 'same-origin', cache: 'no-store' });
    if (!response.ok) return null;
    const data = await response.json();
    return typeof data.access_token === 'string' ? data.access_token : null;
  };
  return navigator.locks ? navigator.locks.request('samosachaat-refresh', refresh) : refresh();
}

export async function logoutSession(): Promise<void> {
  const logout = async () => {
    try { await fetch('/api/auth/logout', { method: 'POST', credentials: 'same-origin' }); }
    finally { clearToken(); sessionChannel?.postMessage('logout'); }
  };
  if (navigator.locks) await navigator.locks.request('samosachaat-refresh', logout);
  else await logout();
}
