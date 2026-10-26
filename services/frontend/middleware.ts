import { NextResponse } from 'next/server';

export function middleware() {
  // Auth is checked client-side via useAuth / localStorage.
  // Middleware is intentionally a pass-through so the
  // /chat?code=... PKCE code exchange can complete before API calls.
  return NextResponse.next();
}

export const config = {
  matcher: [], // No server-side auth blocking
};
