import { NextRequest, NextResponse } from 'next/server';
import { maintenanceResponse, signinMaintenance } from '@/lib/signin-maintenance';

export function middleware(request: NextRequest) {
  if (!signinMaintenance()) return NextResponse.next();
  if (request.nextUrl.pathname === '/chat') {
    if (request.nextUrl.searchParams.has('access_token') || request.nextUrl.searchParams.has('code')) {
      // Strip legacy/new callback material; do not log, echo, capture or redeem it.
      const origin = process.env.APP_PUBLIC_ORIGIN;
      if (!origin) return maintenanceResponse();
      // A configured canonical origin avoids Host/proxy-header trust and internal host redirects.
      const response = NextResponse.redirect(new URL('/signin-maintenance', origin), 303);
      response.headers.set('Cache-Control', 'no-store');
      response.headers.set('Referrer-Policy', 'no-referrer');
      return response;
    }
    return NextResponse.next();
  }
  return maintenanceResponse();
}

export const config = { matcher: ['/login', '/auth/google', '/auth/github', '/chat'] };
