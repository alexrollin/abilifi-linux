// abilifi-linux — CF Linux primitive frag (BEB-1359). Provisions a @cloudflare/sandbox
// container with declarative preinstall (apt + run), then execs in it. Org-scoped.
// Generated via CF qwen-coder (gateway fallback — Kimi swarm was at capacity), then
// completed: imports + Sandbox export + self-init schema + status projection. CANDIDATE — not yet deployed/tested.
import { getSandbox } from '@cloudflare/sandbox';
export { Sandbox } from '@cloudflare/sandbox';

interface Env { DB: D1Database; Sandbox: DurableObjectNamespace; LINUX_GATE?: string }

// SECURITY (11-16, Fable m73484/m73485): the old auth was `startsWith('Bearer bb_')` only — any forged header
// passed, and /linux/exec runs arbitrary bash in a container billed to the account. Interim gate until the
// vault/Ory verification lands (BEB-9807): FAIL CLOSED. With no LINUX_GATE worker secret every route is 503;
// with one, the caller must present it in X-Linux-Gate, compared in constant time, independent of the vault.
function ctEq(a: string, b: string): boolean {
  const enc = new TextEncoder(), x = enc.encode(a), y = enc.encode(b);
  let d = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) d |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return d === 0;
}

let schemaReady: Promise<void> | null = null;
function ensureSchema(env: Env): Promise<void> {
  if (!schemaReady) schemaReady = env.DB.exec(
    'CREATE TABLE IF NOT EXISTS linux_env(org TEXT NOT NULL,id TEXT NOT NULL,spec TEXT,status TEXT,ts INTEGER,PRIMARY KEY(org,id))'
  ).then(() => {});
  return schemaReady;
}

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const url = new URL(req.url);
    const gate = env.LINUX_GATE;
    if (!gate || gate.length < 32) {
      return new Response('Service disabled: awaiting verified auth (BEB-9807 / BEB-9809)', { status: 503 });
    }
    if (!ctEq(req.headers.get('X-Linux-Gate') || '', gate)) {
      return new Response('Unauthorized (gate)', { status: 401 });
    }
    const authHeader = req.headers.get('Authorization');
    if (!authHeader || !authHeader.startsWith('Bearer bb_')) {
      return new Response('Unauthorized', { status: 401 });
    }
    const org = authHeader.substring(13);
    await ensureSchema(env);

    if (req.method === 'POST' && url.pathname === '/linux/provision') {
      const { spec } = await req.json() as any;
      const id = crypto.randomUUID();
      const name = `${org}:${id}`;
      const sb = getSandbox(env.Sandbox, name);
      try {
        await sb.exec('apt-get update');
        if (spec.apt?.length) await sb.exec(`apt-get install -y ${spec.apt.join(' ')}`);
        for (const line of (spec.run || [])) await sb.exec(line);
        await env.DB.prepare('INSERT OR REPLACE INTO linux_env (org, id, spec, status, ts) VALUES (?, ?, ?, ?, ?)')
          .bind(org, id, JSON.stringify(spec), 'ready', Date.now()).run();
        return Response.json({ id, status: 'ready' });
      } catch (e: any) {
        await env.DB.prepare('INSERT OR REPLACE INTO linux_env (org, id, spec, status, ts) VALUES (?, ?, ?, ?, ?)')
          .bind(org, id, JSON.stringify(spec), 'error', Date.now()).run();
        return Response.json({ id, status: 'error', error: e?.message }, { status: 500 });
      }
    }

    if (req.method === 'POST' && url.pathname === '/linux/exec') {
      const { id, code, lang } = await req.json() as any;
      const row = await env.DB.prepare('SELECT id FROM linux_env WHERE org = ? AND id = ?').bind(org, id).first();
      if (!row) return new Response('Not Found', { status: 404 });
      const sb = getSandbox(env.Sandbox, `${org}:${id}`);
      await sb.writeFile('/tmp/x', code);
      const r = await sb.exec(lang === 'python' ? 'python3 /tmp/x' : 'bash /tmp/x');
      return Response.json({ stdout: r.stdout, stderr: r.stderr, exitCode: r.exitCode });
    }

    if (req.method === 'GET' && url.pathname.startsWith('/linux/status/')) {
      const id = url.pathname.split('/').pop();
      const r: any = await env.DB.prepare('SELECT id, status, ts FROM linux_env WHERE org = ? AND id = ?').bind(org, id).first();
      return r ? Response.json(r) : new Response('Not Found', { status: 404 });   // projected — no org leak
    }

    return new Response('Not Found', { status: 404 });
  },
};
