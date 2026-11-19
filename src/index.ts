// abilifi-linux — CF Linux primitive frag (BEB-1359). Provisions a @cloudflare/sandbox
// container with declarative preinstall (apt + run), then execs in it. Org-scoped.
// Generated via CF qwen-coder (gateway fallback — Kimi swarm was at capacity), then
// completed: imports + Sandbox export + self-init schema + status projection. CANDIDATE — not yet deployed/tested.
import { getSandbox } from '@cloudflare/sandbox';
export { Sandbox } from '@cloudflare/sandbox';

interface Env { DB: D1Database; Sandbox: DurableObjectNamespace }

// SECURITY (11-16, Fable m73484/m73485; per-run gates 11-19, Fable m73640/m73643): /linux/exec runs arbitrary bash in a
// container billed to the account, so FAIL CLOSED. Each coder run registers ITS OWN gate: the workflow stores only the
// SHA-256 of a fresh random value in D1 (run_gates, with an expiry) and deletes that row when the run ends. A request must
// present the value in X-Linux-Gate; we hash it and look it up. Runs no longer overwrite one shared secret, so they can be
// parallel. No row = 401. (The old LINUX_GATE worker secret is no longer read.)
async function sha256hex(s: string): Promise<string> {
  const d = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return [...new Uint8Array(d)].map(b => b.toString(16).padStart(2, '0')).join('');
}
async function gateOk(env: Env, presented: string): Promise<boolean> {
  if (presented.length < 32) return false;
  await env.DB.exec('CREATE TABLE IF NOT EXISTS run_gates(hash TEXT PRIMARY KEY, exp INTEGER NOT NULL)');
  const row = await env.DB.prepare('SELECT 1 AS ok FROM run_gates WHERE hash = ? AND exp > ?')
    .bind(await sha256hex(presented), Math.floor(Date.now() / 1000)).first();
  return !!row;
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
    if (!(await gateOk(env, req.headers.get('X-Linux-Gate') || ''))) {
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
      let step = 'start';
      try {
        step = 'apt-get update';
        await sb.exec('apt-get update');
        if (spec.apt?.length) { step = 'apt-get install'; await sb.exec(`apt-get install -y ${spec.apt.join(' ')}`); }
        let i = 0;
        for (const line of (spec.run || [])) { step = `run[${i++}]`; await sb.exec(line); }
        await env.DB.prepare('INSERT OR REPLACE INTO linux_env (org, id, spec, status, ts) VALUES (?, ?, ?, ?, ?)')
          .bind(org, id, JSON.stringify(spec), 'ready', Date.now()).run();
        return Response.json({ id, status: 'ready' });
      } catch (e: any) {
        await env.DB.prepare('INSERT OR REPLACE INTO linux_env (org, id, spec, status, ts) VALUES (?, ?, ?, ?, ?)')
          .bind(org, id, JSON.stringify(spec), 'error', Date.now()).run();
        // diagnostics for the intermittent container-start 500: WHICH exec failed, the error class, its cause and the top of its stack
        const diag = { failed_step: step, name: e?.name, cause: String(e?.cause ?? '').slice(0, 300), stack: String(e?.stack ?? '').split('\n').slice(0, 5).join(' | ').slice(0, 500) };
        console.error(JSON.stringify({ evt: 'provision_error', id, error: e?.message, ...diag }));
        return Response.json({ id, status: 'error', error: e?.message, ...diag }, { status: 500 });
      }
    }

    if (req.method === 'POST' && url.pathname === '/linux/exec') {
      const { id, code, lang } = await req.json() as any;
      const row = await env.DB.prepare('SELECT id FROM linux_env WHERE org = ? AND id = ?').bind(org, id).first();
      if (!row) return new Response('Not Found', { status: 404 });
      const sb = getSandbox(env.Sandbox, `${org}:${id}`);
      try {
        await sb.writeFile('/tmp/x', code);
        const r = await sb.exec(lang === 'python' ? 'python3 /tmp/x' : 'bash /tmp/x');
        return Response.json({ stdout: r.stdout, stderr: r.stderr, exitCode: r.exitCode });
      } catch (e: any) {
        // return the failure as JSON (never a bare 1101) so the caller can see what the container/SDK threw
        return Response.json({ error: String(e?.message || e), name: e?.name, exitCode: -1 }, { status: 500 });
      }
    }

    if (req.method === 'POST' && url.pathname === '/linux/destroy') {
      // free the container (max_instances is small; runs must not leak sandboxes). The row stays as the audit trail.
      const { id } = await req.json() as any;
      const row = await env.DB.prepare('SELECT id FROM linux_env WHERE org = ? AND id = ?').bind(org, id).first();
      if (!row) return new Response('Not Found', { status: 404 });
      let destroyed = false;
      try { await (getSandbox(env.Sandbox, `${org}:${id}`) as any).destroy(); destroyed = true; } catch (_e) { /* already gone */ }
      await env.DB.prepare('UPDATE linux_env SET status = ?, ts = ? WHERE org = ? AND id = ?').bind('destroyed', Date.now(), org, id).run();
      return Response.json({ id, status: 'destroyed', container_destroyed: destroyed });
    }

    if (req.method === 'GET' && url.pathname.startsWith('/linux/status/')) {
      const id = url.pathname.split('/').pop();
      const r: any = await env.DB.prepare('SELECT id, status, ts FROM linux_env WHERE org = ? AND id = ?').bind(org, id).first();
      return r ? Response.json(r) : new Response('Not Found', { status: 404 });   // projected — no org leak
    }

    return new Response('Not Found', { status: 404 });
  },
};
