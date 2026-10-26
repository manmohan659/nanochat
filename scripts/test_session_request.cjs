// Compile lib/session-request.ts to a temporary CommonJS directory before running.
const { test } = require('node:test');
const assert = require('node:assert/strict');
const { withSessionLock, sessionJSON } = require(process.argv[2]);
function aborted(signal) { return new Promise((_, reject) => signal.addEventListener('abort', () => reject(new DOMException('Aborted', 'AbortError')), { once: true })); }
test('hung refresh request aborts instead of indefinitely blocking login', async () => {
  global.fetch = async (_, options) => aborted(options.signal);
  await assert.rejects(sessionJSON('/refresh', undefined, 15), { name: 'AbortError' });
});
test('response body stall stays covered by request deadline', async () => {
  global.fetch = async (_, options) => ({ ok: true, json: () => aborted(options.signal) });
  await assert.rejects(sessionJSON('/refresh', undefined, 15), { name: 'AbortError' });
});
test('busy lock times out without running refresh, then a retry can acquire', async () => {
  let calls = 0;
  Object.defineProperty(global, 'navigator', { configurable: true, value: { locks: { request: (_, options) => aborted(options.signal) } } });
  await assert.rejects(withSessionLock(async () => { calls++; }, 15), { name: 'AbortError' });
  assert.equal(calls, 0);
  navigator.locks.request = async (_, options, callback) => callback();
  await withSessionLock(async () => { calls++; }, 15);
  assert.equal(calls, 1);
});
test('lock remains held throughout request and releases on timeout', async () => {
  let held = false;
  navigator.locks.request = async (_, options, callback) => { held = true; try { return await callback(); } finally { held = false; } };
  global.fetch = async (_, options) => { assert.equal(held, true); return aborted(options.signal); };
  await assert.rejects(withSessionLock(() => sessionJSON('/refresh', undefined, 15), 5), { name: 'AbortError' });
  assert.equal(held, false);
});
test('401 means signed out; transient server errors allow visible retry', async () => {
  global.fetch = async () => ({ ok: false, status: 401 });
  assert.equal(await sessionJSON('/refresh'), null);
  global.fetch = async () => ({ ok: false, status: 503 });
  await assert.rejects(sessionJSON('/refresh'), /unavailable/);
});
