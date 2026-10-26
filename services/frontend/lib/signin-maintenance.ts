import { NextResponse } from 'next/server';

/** Server-only rollout gate. Existing API traffic, refresh, and logout remain available. */
export function signinMaintenance(): boolean {
  return process.env.SIGNIN_MAINTENANCE === 'true';
}

export function maintenanceResponse(): NextResponse {
  return new NextResponse('<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Sign-in temporarily unavailable</title><main><h1>We are updating sign-in</h1><p>Please try again in a few minutes. Your saved conversations are unchanged.</p><p><a href="/login">Try signing in again</a></p></main></html>', {
    status: 503,
    headers: { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store', 'Retry-After': '60', 'Referrer-Policy': 'no-referrer', 'X-Content-Type-Options': 'nosniff' },
  });
}
