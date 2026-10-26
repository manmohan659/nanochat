import { NextResponse } from 'next/server';
import { maintenanceResponse, signinMaintenance } from '@/lib/signin-maintenance';
import { randomBytes, createHash } from 'node:crypto';

export const runtime = 'nodejs';

const providers = new Set(['google', 'github']);

type RouteContext = {
  params: Promise<{ provider: string }>;
};

function authPublicBaseUrl(): string | null {
  const raw =
    process.env.AUTH_PUBLIC_URL ||
    process.env.NEXT_PUBLIC_AUTH_SERVICE_URL ||
    process.env.AUTH_SERVICE_URL;
  return raw ? raw.replace(/\/+$/, '') : null;
}

export async function GET(_request: Request, { params }: RouteContext) {
  if (signinMaintenance()) return maintenanceResponse();
  const { provider } = await params;
  if (!providers.has(provider)) {
    return NextResponse.json({ error: 'unknown auth provider' }, { status: 404 });
  }

  const authBaseUrl = authPublicBaseUrl();
  if (!authBaseUrl) {
    return NextResponse.json(
      { error: 'AUTH_PUBLIC_URL or AUTH_SERVICE_URL is not configured' },
      { status: 503 },
    );
  }

  const verifier = randomBytes(32).toString('base64url');
  const challenge = createHash('sha256').update(verifier).digest('base64url');
  const response = NextResponse.redirect(`${authBaseUrl}/auth/${provider}?code_challenge=${challenge}`);
  response.cookies.set('samosachaat_login_verifier', verifier, { httpOnly: true, secure: process.env.NODE_ENV === 'production', sameSite: 'lax', path: '/', maxAge: 600 });
  response.headers.set('Cache-Control', 'no-store');
  return response;
}
