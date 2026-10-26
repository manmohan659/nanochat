# Coordinated sign-in security rollout

The session protocol changes from bearer-query callbacks to PKCE-bound one-time codes. Do not serve a mixed frontend/auth pair to new sign-ins. No legacy bearer-query fallback is added to the new protocol.

`SIGNIN_MAINTENANCE=true` is a **server-only** runtime setting on frontend and auth. Set frontend `APP_PUBLIC_ORIGIN` to the canonical HTTPS origin before activation; callback cleanup uses this trusted origin rather than proxy/Host headers. Exact lowercase `true` enables it. The frontend serves a clear503/Retry-After60 page for login/provider starts and redirects callback query material to a clean maintenance URL without consuming or echoing it. Phase2 exchange is also gated. Auth rejects provider starts/callbacks before provider calls or request logging. Health, existing authenticated API requests, refresh and logout are not gated. Already-issued access tokens remain valid until expiry/signing-key change. Browser reloads can require sign-in again; this is a bounded sign-in maintenance window, not a zero-impact rollout.

## Release order

1. Verify a recoverable database backup and preserve current successful deployment IDs. Do not migrate without the backup gate.
2. Apply additive migration005 through the chat-api release/preDeploy and verify Alembic revision plus chat health. It adds login-code/family/refresh tables only; existing auth remains compatible with the added tables.
3. Set frontend APP_PUBLIC_ORIGIN to the canonical HTTPS origin, then enable maintenance on frontend and auth. Deploy the **phase1 maintenance bridge frontend first**, then bridge auth. Verify frontend login503, callback query303 to the clean maintenance URL, auth provider/callback503, and health/API availability. Do not proceed if those gates are not live.
4. Configure frontend server-only INTERNAL_API_KEY matching auth, private AUTH_SERVICE_URL, public AUTH_PUBLIC_URL and canonical NEXT_PUBLIC_APP_URL. Keep both maintenance settings true. Deploy phase2 frontend and auth; verify the exact deployment IDs reach SUCCESS, health and source revision. No protocol traffic should cross mixed versions while these gates are active.
5. Disable auth maintenance and verify new auth's challenge requirement; frontend maintenance stays enabled. Then disable frontend maintenance only after both services are ready. Runtime setting changes may trigger new deployments; verify those exact deployments too.
6. Complete authorized real-provider sign-in through the canonical frontend, then refresh and logout. Local mocked-provider tests do not prove production OAuth registrations. Re-enable frontend maintenance if this final gate fails and follow paired rollback.

## Rollback

Keep/re-enable maintenance before restoring applications. Roll auth AND frontend back to the known **maintenance-capable phase1 bridge** pair; verify both are healthy before reopening sign-in. Keep additive005 tables; never drop them as an application rollback step. Restore only current valid credentials—revoked credentials are not rollback material. Database restore is a separate reviewed operation and is not needed for ordinary application rollback.

## Validation

Auth unit/integration suites cover maintenance start/callback rejection and unchanged health/auth gates. `scripts/test_signin_maintenance.py` runs built production Next servers against synthetic localhost traffic with runtime maintenance true and false, checks callback sanitization and no application credential logging, and confirms unaffected APIs/refresh. Run `npm ci --ignore-scripts`, `npm run build` in services/frontend, then `python3 scripts/test_signin_maintenance.py` from repo root with a supported Node on PATH. Existing app session tests cover single-use codes, PKCE rejection, refresh replay and logout.

No real provider login or production mutation is performed by these tests. Platform/proxy access-log behavior is outside the application logging assertion; pre-existing legacy callbacks may already have reached upstream request logs before maintenance activation.
