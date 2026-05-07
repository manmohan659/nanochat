import { NextRequest } from 'next/server';
import { getTraceId, logger, logRouteError, textWithTrace, upstreamHeaders } from '@/lib/logger';

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

async function proxyUpstream(body: unknown, upstreamUrl: string, req: NextRequest, traceId: string) {
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
    },
  });
}

function mockEcho(body: StreamBody, traceId: string): Response {
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
    },
  });
}

export async function POST(req: NextRequest) {
  const traceId = getTraceId(req);
  logger.info({ trace_id: traceId, path: req.nextUrl.pathname }, 'stream_request_start');

  let body: StreamBody;
  try {
    body = (await req.json()) as StreamBody;
  } catch {
    return textWithTrace('Invalid JSON', { status: 400 }, traceId);
  }

  const upstream = process.env.CHAT_API_URL;
  const hasAuth = Boolean(req.headers.get('authorization'));

  if (upstream) {
    try {
      // If we have a conversationId and auth, use the persisted messages endpoint
      const convId = body.conversationId;
      if (convId && hasAuth) {
        // Chat-api expects {content, temperature, max_tokens, top_k}
        // Extract the last user message as the content
        const lastUserMsg = [...body.messages].reverse().find(m => m.role === 'user');
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
        );
      }
      // Fallback to direct chat completions (no persistence)
      return await proxyUpstream(
        body,
        `${upstream.replace(/\/$/, '')}/chat/completions`,
        req,
        traceId,
      );
    } catch (err) {
      logRouteError('stream_upstream_failed_using_mock', err, traceId);
    }
  }

  return mockEcho(body, traceId);
}
