import { NextResponse } from 'next/server';
import { maintenanceResponse, signinMaintenance } from '@/lib/signin-maintenance';
export const dynamic = 'force-dynamic';
export function GET() {
  return signinMaintenance() ? maintenanceResponse() : new NextResponse(null, { status: 303, headers: { Location: '/login' } });
}
