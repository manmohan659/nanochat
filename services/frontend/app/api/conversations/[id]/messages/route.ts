import { NextRequest } from 'next/server';
import { authHeader, getTraceId, logRouteError, textWithTrace, upstreamHeaders } from '@/lib/logger';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

const CHAT_API = process.env.CHAT_API_URL || 'http://chat-api:8002';

type RouteContext = { params: Promise<{ id: string }> };

export async function POST(req: NextRequest, { params }: RouteContext) {
  const { id } = await params;
  const traceId = getTraceId(req);
  if (!authHeader(req)) return textWithTrace('Unauthorized', { status: 401 }, traceId);

  const body = await req.json();

  try {
    const res = await fetch(`${CHAT_API}/api/conversations/${id}/messages`, {
      method: 'POST',
      headers: upstreamHeaders(req, traceId),
      body: JSON.stringify(body),
    });

    if (!res.ok || !res.body) {
      return textWithTrace(`Backend error: ${res.status}`, { status: res.status }, res.headers.get('x-trace-id') || traceId);
    }

    // Stream SSE through
    return new Response(res.body, {
      headers: {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache, no-transform',
        Connection: 'keep-alive',
        'x-trace-id': res.headers.get('x-trace-id') || traceId,
      },
    });
  } catch (err) {
    logRouteError('conversation_message_post_error', err, traceId, { conversation_id: id });
    return textWithTrace('Internal Server Error', { status: 500 }, traceId);
  }
}
