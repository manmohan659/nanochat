import { NextRequest, NextResponse } from 'next/server';
export const runtime = 'nodejs';
const refreshCookie = 'samosachaat_refresh';
const verifierCookie = 'samosachaat_login_verifier';
type Context = { params: Promise<{ action: string }> };
async function boundedJSON(body: ReadableStream<Uint8Array> | null, limit: number): Promise<Record<string, unknown>> {
  if (!body) throw new Error('Missing body');
  const reader = body.getReader(); const chunks: Uint8Array[] = []; let size = 0;
  try {
    while (true) { const item = await reader.read(); if (item.done) break; size += item.value.length; if (size > limit) { await reader.cancel(); throw new Error('Body too large'); } chunks.push(item.value); }
    const parsed = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error('Expected object');
    return parsed;
  } finally { reader.releaseLock(); }
}

export async function POST(request: NextRequest, { params }: Context) {
  const { action } = await params;
  if (!['exchange', 'refresh', 'logout'].includes(action)) return NextResponse.json({ error: 'Not found' }, { status: 404 });
  // Browser requests must be same-origin; reject cross-site form/credential requests.
  const origin = request.headers.get('origin');
  const expectedOrigin = process.env.NEXT_PUBLIC_APP_URL || new URL(request.url).origin;
  if (!origin || origin !== new URL(expectedOrigin).origin) return NextResponse.json({ error: 'Forbidden' }, { status: 403 });
  const key = process.env.INTERNAL_API_KEY;
  const auth = process.env.AUTH_SERVICE_URL;
  if (!key || !auth) return NextResponse.json({ error: 'Authentication unavailable' }, { status: 503 });
  let payload: Record<string, string>;
  if (action === 'exchange') {
    const verifier = request.cookies.get(verifierCookie)?.value;
    const data = await boundedJSON(request.body, 4096).catch(() => ({} as Record<string, unknown>));
    if (!verifier || typeof data.code !== 'string' || data.code.length > 128) return NextResponse.json({ error: 'Restart sign-in' }, { status: 401 });
    payload = { code: data.code, verifier };
  } else {
    const token = request.cookies.get(refreshCookie)?.value;
    if (!token) return NextResponse.json({ error: 'Sign in again' }, { status: 401 });
    payload = { token };
  }
  try {
    const upstream = await fetch(`${auth.replace(/\/+$/, '')}/auth/${action}`, { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Internal-API-Key': key }, body: JSON.stringify(payload), cache: 'no-store', redirect: 'error', signal: AbortSignal.timeout(10000) });
    const data = await boundedJSON(upstream.body, 16384);
    if (upstream.ok && action !== 'logout' && !(typeof data.access_token === 'string' && data.access_token.length > 0 && data.access_token.length <= 8192 && typeof data.refresh_token === 'string' && data.refresh_token.length > 0 && data.refresh_token.length <= 8192 && Number.isInteger(data.access_expires_in) && Number(data.access_expires_in) > 0 && Number(data.access_expires_in) <= 3600 && Number.isInteger(data.refresh_expires_in) && Number(data.refresh_expires_in) > 0 && Number(data.refresh_expires_in) <= 604800)) throw new Error('Invalid auth response');
    const response = NextResponse.json(upstream.ok ? (action === 'logout' ? { ok: true } : { access_token: data.access_token, expires_in: data.access_expires_in }) : { error: 'Sign in again' }, { status: upstream.ok ? 200 : upstream.status, headers: { 'Cache-Control': 'no-store' } });
    const opts = { httpOnly: true, secure: process.env.NODE_ENV === 'production', sameSite: 'lax' as const, path: '/' };
    if (action === 'exchange') response.cookies.set(verifierCookie, '', { ...opts, maxAge: 0 });
    if (upstream.ok && action !== 'logout' && typeof data.refresh_token === 'string') response.cookies.set(refreshCookie, data.refresh_token, { ...opts, maxAge: Number(data.refresh_expires_in) });
    if (action === 'logout' || upstream.status === 401) response.cookies.set(refreshCookie, '', { ...opts, maxAge: 0 });
    return response;
  } catch {
    const response = NextResponse.json({ error: 'Authentication unavailable' }, { status: 503, headers: { 'Cache-Control': 'no-store' } });
    if (action === 'logout') response.cookies.set(refreshCookie, '', { httpOnly: true, secure: process.env.NODE_ENV === 'production', sameSite: 'lax', path: '/', maxAge: 0 });
    return response;
  }
}
