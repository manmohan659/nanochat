import { NextRequest } from 'next/server';
import {
  authHeader,
  getSessionTraceId,
  getTraceId,
  logRouteError,
  textWithTrace,
  upstreamHeaders,
} from '@/lib/logger';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

const CHAT_API = process.env.CHAT_API_URL || 'http://chat-api:8002';

type RouteContext = { params: Promise<{ id: string }> };

export async function POST(req: NextRequest, { params }: RouteContext) {
  const { id } = await params;
  const traceId = getTraceId(req);
  const sessionTraceId = getSessionTraceId(req);
  if (!authHeader(req)) {
    return textWithTrace('Unauthorized', { status: 401 }, traceId, sessionTraceId);
  }

  const body = await req.json();

  try {
    const res = await fetch(`${CHAT_API}/api/conversations/${id}/messages`, {
      method: 'POST',
      headers: upstreamHeaders(req, traceId),
      body: JSON.stringify(body),
    });

    if (!res.ok || !res.body) {
      return textWithTrace(
        `Backend error: ${res.status}`,
        { status: res.status },
        res.headers.get('x-trace-id') || traceId,
        sessionTraceId,
      );
    }

    return new Response(res.body, {
      headers: {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache, no-transform',
        Connection: 'keep-alive',
        'x-trace-id': res.headers.get('x-trace-id') || traceId,
        ...(sessionTraceId ? { 'x-session-trace-id': sessionTraceId } : {}),
      },
    });
  } catch (err) {
    logRouteError('conversation_message_post_error', err, traceId, {
      conversation_id: id,
      session_trace_id: sessionTraceId,
    });
    return textWithTrace('Internal Server Error', { status: 500 }, traceId, sessionTraceId);
  }
}
