import { NextRequest } from 'next/server';
import {
  getSessionTraceId,
  getTraceId,
  logger,
  logRouteError,
  textWithTrace,
  upstreamHeaders,
} from '@/lib/logger';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

interface StreamBody {
  messages: Array<{ role: string; content: string }>;
  model?: string;
  temperature?: number;
  topK?: number;
  maxTokens?: number;
  conversationId?: string;
}

const encoder = new TextEncoder();

function sseEvent(data: Record<string, unknown>) {
  return encoder.encode(`data: ${JSON.stringify(data)}\n\n`);
}

async function proxyUpstream(
  body: unknown,
  upstreamUrl: string,
  req: NextRequest,
  traceId: string,
  sessionTraceId: string | null,
) {
  const upstream = await fetch(upstreamUrl, {
    method: 'POST',
    headers: upstreamHeaders(req, traceId),
    body: JSON.stringify(body),
  });

  if (!upstream.ok || !upstream.body) {
    throw new Error(`upstream HTTP ${upstream.status}`);
  }

  return new Response(upstream.body, {
    headers: {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache, no-transform',
      Connection: 'keep-alive',
      'x-trace-id': upstream.headers.get('x-trace-id') || traceId,
      ...(sessionTraceId ? { 'x-session-trace-id': sessionTraceId } : {}),
    },
  });
}

function mockEcho(body: StreamBody, traceId: string, sessionTraceId: string | null): Response {
  const last = body.messages[body.messages.length - 1]?.content ?? '';
  const greetings = [
    'Namaste! ',
    "Here's what I can offer for that question: ",
    "Let's think about it together. ",
  ];
  const greeting = greetings[Math.floor(Math.random() * greetings.length)];
  const echo = last.trim() ? `You asked: "${last.trim()}".` : 'I am listening.';
  const full = `${greeting}${echo}\n\nThis is a mock response from the samosaChaat frontend — once the chat service is wired, real streaming tokens will land here.`;

  const stream = new ReadableStream({
    async start(controller) {
      const words = full.split(/(\s+)/);
      for (const w of words) {
        controller.enqueue(sseEvent({ token: w, gpu: 0 }));
        await new Promise((r) => setTimeout(r, 25));
      }
      controller.enqueue(sseEvent({ done: true }));
      controller.close();
    },
  });

  return new Response(stream, {
    headers: {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache, no-transform',
      Connection: 'keep-alive',
      'x-trace-id': traceId,
      ...(sessionTraceId ? { 'x-session-trace-id': sessionTraceId } : {}),
    },
  });
}

export async function POST(req: NextRequest) {
  const traceId = getTraceId(req);
  const sessionTraceId = getSessionTraceId(req);
  logger.info(
    { trace_id: traceId, session_trace_id: sessionTraceId, path: req.nextUrl.pathname },
    'stream_request_start',
  );

  let body: StreamBody;
  try {
    body = (await req.json()) as StreamBody;
  } catch {
    return textWithTrace('Invalid JSON', { status: 400 }, traceId, sessionTraceId);
  }

  const upstream = process.env.CHAT_API_URL;
  const hasAuth = Boolean(req.headers.get('authorization'));

  if (upstream) {
    try {
      const convId = body.conversationId;
      if (convId && hasAuth) {
        const lastUserMsg = [...body.messages].reverse().find((m) => m.role === 'user');
        const chatApiBody = {
          content: lastUserMsg?.content ?? '',
          temperature: body.temperature,
          max_tokens: body.maxTokens,
          top_k: body.topK,
        };
        return await proxyUpstream(
          chatApiBody,
          `${upstream.replace(/\/$/, '')}/api/conversations/${convId}/messages`,
          req,
          traceId,
          sessionTraceId,
        );
      }
      return await proxyUpstream(
        body,
        `${upstream.replace(/\/$/, '')}/chat/completions`,
        req,
        traceId,
        sessionTraceId,
      );
    } catch (err) {
      logRouteError('stream_upstream_failed_using_mock', err, traceId, {
        session_trace_id: sessionTraceId,
      });
    }
  }

  return mockEcho(body, traceId, sessionTraceId);
}
