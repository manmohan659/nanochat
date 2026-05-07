import { NextRequest } from 'next/server';
import { authHeader, getTraceId, jsonWithTrace, logRouteError, upstreamHeaders } from '@/lib/logger';

export const runtime = 'nodejs';

const CHAT_API = process.env.CHAT_API_URL || 'http://chat-api:8002';

export async function GET(req: NextRequest) {
  const traceId = getTraceId(req);
  if (!authHeader(req)) return jsonWithTrace({ error: 'Unauthorized' }, { status: 401 }, traceId);

  try {
    const res = await fetch(`${CHAT_API}/api/admin/users`, {
      headers: upstreamHeaders(req, traceId),
    });
    const data = await res.json();
    return jsonWithTrace(data, { status: res.status }, res.headers.get('x-trace-id') || traceId);
  } catch (err) {
    logRouteError('admin_users_proxy_error', err, traceId);
    return jsonWithTrace({ error: 'Failed to fetch admin data' }, { status: 500 }, traceId);
  }
}
