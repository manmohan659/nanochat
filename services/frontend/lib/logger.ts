import pino from 'pino';
import { NextRequest, NextResponse } from 'next/server';

export const logger = pino({
  name: 'samosachaat-frontend',
  level: process.env.LOG_LEVEL || 'info',
  messageKey: 'message',
  timestamp: () => `,"timestamp":"${new Date().toISOString()}"`,
  formatters: {
    level: (label) => ({ level: label }),
  },
  base: {
    service: 'frontend',
    environment: process.env.ENVIRONMENT || process.env.NODE_ENV || 'development',
  },
});

export function getTraceId(req: NextRequest): string {
  return req.headers.get('x-trace-id') || req.headers.get('x-request-id') || crypto.randomUUID().replace(/-/g, '');
}

export function authHeader(req: NextRequest): string | null {
  return req.headers.get('authorization');
}

export function upstreamHeaders(
  req: NextRequest,
  traceId: string,
  options: { contentType?: boolean } = {},
): Record<string, string> {
  const headers: Record<string, string> = {
    'x-trace-id': traceId,
  };
  const auth = authHeader(req);
  if (auth) headers.Authorization = auth;
  if (options.contentType !== false) headers['Content-Type'] = 'application/json';
  return headers;
}

export function jsonWithTrace(body: unknown, init: ResponseInit, traceId: string) {
  const response = NextResponse.json(body, init);
  response.headers.set('x-trace-id', traceId);
  return response;
}

export function textWithTrace(body: BodyInit | null, init: ResponseInit, traceId: string) {
  const response = new Response(body, init);
  response.headers.set('x-trace-id', traceId);
  return response;
}

export function logRouteError(event: string, err: unknown, traceId: string, extra: Record<string, unknown> = {}) {
  logger.error(
    {
      ...extra,
      trace_id: traceId,
      error: err instanceof Error ? err.message : String(err),
    },
    event,
  );
}
