import { NextResponse } from 'next/server';

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

  return NextResponse.redirect(`${authBaseUrl}/auth/${provider}`);
}
