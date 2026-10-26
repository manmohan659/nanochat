// Bound lock acquisition separately from the request. Never bypass a busy lock.
export const SESSION_WAIT_MS = 10000;
export async function withSessionLock<T>(operation: () => Promise<T>, timeout = SESSION_WAIT_MS): Promise<T> {
  if (!navigator.locks) return operation();
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeout);
  try {
    return await navigator.locks.request('samosachaat-refresh', { signal: controller.signal }, async () => {
      clearTimeout(timer);
      return operation();
    });
  } finally { clearTimeout(timer); }
}

export async function sessionJSON(path: string, body?: object, timeout = SESSION_WAIT_MS): Promise<Record<string, unknown> | null> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeout);
  try {
    const response = await fetch(path, { method: 'POST', credentials: 'same-origin', cache: 'no-store', signal: controller.signal,
      ...(body ? { headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) } : {}) });
    if (!response.ok) {
      if (response.status === 401) return null;
      throw new Error('Session service unavailable');
    }
    return await response.json();
  } finally { clearTimeout(timer); }
}
