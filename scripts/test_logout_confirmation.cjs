const { test } = require('node:test');
const assert = require('node:assert/strict');
global.window = {};
global.BroadcastChannel = undefined;
global.localStorage = { removeItem() {} };
Object.defineProperty(global, 'navigator', { configurable: true, value: { locks: { request: async (_, options, callback) => callback() } } });
const auth = require(process.argv[2]);
test('lock refusal never falsely clears the local session or calls logout endpoint', async () => {
  auth.setToken('opaque-test-token'); let requests = 0;
  global.fetch = async () => { requests++; };
  navigator.locks.request = async () => { throw new DOMException('Lock timed out', 'AbortError'); };
  await assert.rejects(auth.logoutSession(), { name: 'AbortError' });
  assert.equal(auth.getToken(), 'opaque-test-token'); assert.equal(requests, 0);
  auth.clearToken();
});
test('server failure keeps session and allows explicit retry; confirmed retry clears', async () => {
  auth.setToken('opaque-test-token');
  navigator.locks.request = async (_, options, callback) => callback();
  global.fetch = async () => ({ ok: false, status: 503 });
  await assert.rejects(auth.logoutSession()); assert.equal(auth.getToken(), 'opaque-test-token');
  global.fetch = async () => ({ ok: true, json: async () => ({ ok: true }) });
  await auth.logoutSession(); assert.equal(auth.getToken(), null);
});
test('already expired server session (401) confirms signed out', async () => {
  auth.setToken('opaque-test-token'); global.fetch = async () => ({ ok: false, status: 401 });
  await auth.logoutSession(); assert.equal(auth.getToken(), null);
});
