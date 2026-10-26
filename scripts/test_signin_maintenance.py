"""Verify runtime sign-in gates against built Next frontends; loopback synthetic traffic only."""
import http.server, socket, threading, subprocess, os, time, json, urllib.request, urllib.error, pathlib, tempfile, shutil
BASE=pathlib.Path(__file__).resolve().parents[1]
NODE=os.environ.get('NODE_BINARY') or shutil.which('node')
if not NODE: raise RuntimeError('Node is required; build the frontend first')
PHASE2=(BASE/'services/frontend/app/api/auth/[action]/route.ts').exists()
def free_port():
    with socket.socket() as s:s.bind(('127.0.0.1',0));return s.getsockname()[1]
class Upstream(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        assert self.headers.get('X-Internal-API-Key')=='synthetic-internal'
        data=json.dumps({'access_token':'synthetic-access','refresh_token':'synthetic-refresh','access_expires_in':900,'refresh_expires_in':600}).encode()
        self.send_response(200);self.send_header('Content-Type','application/json');self.end_headers();self.wfile.write(data)
    def log_message(self,*args):pass
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,*args):return None
up=free_port();server=http.server.ThreadingHTTPServer(('127.0.0.1',up),Upstream);threading.Thread(target=server.serve_forever,daemon=True).start()
def check(name,enabled):
    port=free_port();origin=f'http://localhost:{port}'
    env={'PATH':os.path.dirname(NODE)+':/usr/bin:/bin','HOME':os.environ['HOME'],'NODE_ENV':'production','NEXT_PUBLIC_APP_URL':origin,'APP_PUBLIC_ORIGIN':origin,'AUTH_PUBLIC_URL':f'http://127.0.0.1:{up}','AUTH_SERVICE_URL':f'http://127.0.0.1:{up}','INTERNAL_API_KEY':'synthetic-internal','SIGNIN_MAINTENANCE':str(enabled).lower(),'NEXT_TELEMETRY_DISABLED':'1'}
    logs=tempfile.TemporaryFile();p=subprocess.Popen([NODE,'node_modules/next/dist/bin/next','start','-H','127.0.0.1','-p',str(port)],cwd=BASE/'services/frontend',env=env,stdout=logs,stderr=logs)
    def req(path,data=None,headers=None):
        r=urllib.request.Request(origin+path,data=None if data is None else json.dumps(data).encode(),headers=headers or {},method='GET' if data is None else 'POST')
        try:response=urllib.request.build_opener(NoRedirect).open(r,timeout=10)
        except urllib.error.HTTPError as e:response=e
        return response.status,response.headers,response.read()
    try:
        for _ in range(100):
            try:
                if req('/api/health')[0]==200:break
            except Exception:time.sleep(.1)
        else:raise AssertionError('Next did not start')
        if enabled:
            for path in ['/login','/auth/google','/auth/github','/signin-maintenance']:
                status,h,b=req(path);assert status==503,(path,status)
                assert h['Retry-After']=='60' and h['Cache-Control']=='no-store'
                assert 'Location' not in h
            for field in ['access_token','code']:
                status,h,b=req('/chat?'+field+'=synthetic-sensitive-marker')
                assert status==303 and h['Location']==origin+'/signin-maintenance', (status, h.get('Location', '').replace('synthetic-sensitive-marker', '[redacted-test]'))
                assert b'synthetic-sensitive-marker' not in b
            assert req('/chat')[0]==200
            assert req('/api/conversations')[0]==401
            if PHASE2:
                assert req('/api/auth/exchange',{'code':'c'*43})[0]==503
                status,h,b=req('/api/auth/refresh',{}, {'Origin':origin,'Cookie':'samosachaat_refresh=synthetic-refresh'})
                assert status==200 and b'synthetic-refresh' not in b
        else:
            status,h,b=req('/auth/google');assert status==307
            assert ('code_challenge=' in h['Location']) == (PHASE2)
            assert req('/login')[0]==200
        logs.seek(0);assert b'synthetic-sensitive-marker' not in logs.read()
        print('PASS',name,'maintenance='+str(enabled),'runtime gate, callbacks, APIs, no application credential logging')
    finally:p.terminate();p.wait(timeout=10);logs.close()
try:
    for enabled in [True,False]:check('session-release' if PHASE2 else 'maintenance-bridge',enabled)
finally:server.shutdown()
