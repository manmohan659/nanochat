const TOKEN_KEY = 'samosachaat_access_token';
const USER_KEY = 'samosachaat_user';
const SESSION_TRACE_KEY = 'samosachaat_session_trace_id';

export interface TokenUser {
  name: string;
  email: string;
}

export function getToken(): string | null {
  if (typeof window === 'undefined') return null;
  return localStorage.getItem(TOKEN_KEY);
}

export function setToken(token: string): void {
  localStorage.setItem(TOKEN_KEY, token);
  // Decode JWT payload to persist basic user info
  try {
    const payload = JSON.parse(atob(token.split('.')[1]));
    const user: TokenUser = {
      name: payload.name || payload.email || 'User',
      email: payload.email || '',
    };
    localStorage.setItem(USER_KEY, JSON.stringify(user));
  } catch {
    /* malformed JWT — ignore */
  }
}

export function clearToken(): void {
  localStorage.removeItem(TOKEN_KEY);
  localStorage.removeItem(USER_KEY);
}

export function isAuthenticated(): boolean {
  return !!getToken();
}

export function getUser(): TokenUser | null {
  if (typeof window === 'undefined') return null;
  try {
    const raw = localStorage.getItem(USER_KEY);
    return raw ? (JSON.parse(raw) as TokenUser) : null;
  } catch {
    return null;
  }
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
