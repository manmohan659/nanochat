import { NextRequest } from 'next/server';
import { authHeader, getSessionTraceId, getTraceId, jsonWithTrace, logRouteError, upstreamHeaders } from '@/lib/logger';

export const runtime = 'nodejs';

const CHAT_API = process.env.CHAT_API_URL || 'http://chat-api:8002';

type RouteContext = { params: Promise<{ id: string }> };

export async function GET(req: NextRequest, { params }: RouteContext) {
  const { id } = await params;
  const traceId = getTraceId(req);
  const sessionTraceId = getSessionTraceId(req);
  if (!authHeader(req)) return jsonWithTrace({ error: 'Unauthorized' }, { status: 401 }, traceId, sessionTraceId);

  try {
    const res = await fetch(`${CHAT_API}/api/conversations/${id}`, {
      headers: upstreamHeaders(req, traceId, { contentType: false }),
    });
    return jsonWithTrace(await res.json(), { status: res.status }, res.headers.get('x-trace-id') || traceId, sessionTraceId);
  } catch (err) {
    logRouteError('conversation_get_error', err, traceId, { conversation_id: id, session_trace_id: sessionTraceId });
    return jsonWithTrace({ error: 'Failed to fetch conversation' }, { status: 500 }, traceId, sessionTraceId);
  }
}

export async function PUT(req: NextRequest, { params }: RouteContext) {
  const { id } = await params;
  const traceId = getTraceId(req);
  const sessionTraceId = getSessionTraceId(req);
  if (!authHeader(req)) return jsonWithTrace({ error: 'Unauthorized' }, { status: 401 }, traceId, sessionTraceId);

  const body = await req.json();
  try {
    const res = await fetch(`${CHAT_API}/api/conversations/${id}`, {
      method: 'PUT',
      headers: upstreamHeaders(req, traceId),
      body: JSON.stringify(body),
    });
    return jsonWithTrace(await res.json(), { status: res.status }, res.headers.get('x-trace-id') || traceId, sessionTraceId);
  } catch (err) {
    logRouteError('conversation_update_error', err, traceId, { conversation_id: id, session_trace_id: sessionTraceId });
    return jsonWithTrace({ error: 'Failed to update conversation' }, { status: 500 }, traceId, sessionTraceId);
  }
}

export async function DELETE(req: NextRequest, { params }: RouteContext) {
  const { id } = await params;
  const traceId = getTraceId(req);
  const sessionTraceId = getSessionTraceId(req);
  if (!authHeader(req)) return jsonWithTrace({ error: 'Unauthorized' }, { status: 401 }, traceId, sessionTraceId);

  try {
    const res = await fetch(`${CHAT_API}/api/conversations/${id}`, {
      method: 'DELETE',
      headers: upstreamHeaders(req, traceId, { contentType: false }),
    });
    return jsonWithTrace({ ok: true }, { status: res.status }, res.headers.get('x-trace-id') || traceId, sessionTraceId);
  } catch (err) {
    logRouteError('conversation_delete_error', err, traceId, { conversation_id: id, session_trace_id: sessionTraceId });
    return jsonWithTrace({ error: 'Failed to delete conversation' }, { status: 500 }, traceId, sessionTraceId);
  }
}
