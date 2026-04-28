import { NextRequest, NextResponse } from 'next/server';

export const runtime = 'nodejs';

const CHAT_API = process.env.CHAT_API_URL || 'http://chat-api:8002';

export async function GET(req: NextRequest) {
  const auth = req.headers.get('authorization');
  if (!auth) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  try {
    const res = await fetch(`${CHAT_API}/api/admin/users`, {
      headers: { Authorization: auth, 'Content-Type': 'application/json' },
    });
    const data = await res.json();
    return NextResponse.json(data, { status: res.status });
  } catch (err) {
    console.error('[admin/users] proxy error:', err);
    return NextResponse.json({ error: 'Failed to fetch admin data' }, { status: 500 });
  }
}
