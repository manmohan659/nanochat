import { NextRequest } from 'next/server';
import { authHeader, getTraceId, jsonWithTrace, logRouteError, upstreamHeaders } from '@/lib/logger';

export const runtime = 'nodejs';

const CHAT_API = process.env.CHAT_API_URL || 'http://chat-api:8002';

export async function GET(req: NextRequest) {
  const traceId = getTraceId(req);
  if (!authHeader(req)) return jsonWithTrace({ error: 'Unauthorized' }, { status: 401 }, traceId);

  try {
    const res = await fetch(`${CHAT_API}/api/conversations`, {
      headers: upstreamHeaders(req, traceId),
    });
    const data = await res.json();
    return jsonWithTrace(data, { status: res.status }, res.headers.get('x-trace-id') || traceId);
  } catch (err) {
    logRouteError('conversations_proxy_error', err, traceId);
    return jsonWithTrace({ conversations: [] }, {}, traceId);
  }
}

export async function POST(req: NextRequest) {
  const traceId = getTraceId(req);
  if (!authHeader(req)) return jsonWithTrace({ error: 'Unauthorized' }, { status: 401 }, traceId);

  const body = await req.json();
  try {
    const res = await fetch(`${CHAT_API}/api/conversations`, {
      method: 'POST',
      headers: upstreamHeaders(req, traceId),
      body: JSON.stringify(body),
    });
    const data = await res.json();
    return jsonWithTrace(data, { status: res.status }, res.headers.get('x-trace-id') || traceId);
  } catch (err) {
    logRouteError('conversation_create_error', err, traceId);
    return jsonWithTrace({ error: 'Failed to create conversation' }, { status: 500 }, traceId);
  }
}
