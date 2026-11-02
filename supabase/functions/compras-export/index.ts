// compras-export — proyecto wzkqaxgsqgbokkmxarbd (Eatalia / Scanzano)
// Devuelve líneas de compra para la capa Compras HQ. Solo lectura.
//
// Autenticación sin secreto compartido: quien llama manda en `x-hq-key` la llave
// service_role del proyecto btbox. Esta función se la presenta a btbox
// (rpc compras_hq_autorizar_export); si btbox responde true, la llave es suya y se exporta.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const BTBOX_URL = "https://btboxlwfqcbrdfrlnwln.supabase.co";
const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

async function autorizado(key: string | null): Promise<boolean> {
  if (!key || key.length < 40) return false;
  try {
    const r = await fetch(`${BTBOX_URL}/rest/v1/rpc/compras_hq_autorizar_export`, {
      method: "POST",
      headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: "{}",
    });
    return r.ok && (await r.json()) === true;
  } catch {
    return false;
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "POST" }, 405);
  if (!(await autorizado(req.headers.get("x-hq-key")))) return json({ error: "no autorizado" }, 401);

  const body = await req.json().catch(() => ({}));
  const desde = /^\d{4}-\d{2}-\d{2}$/.test(body.desde ?? "") ? body.desde : "2022-01-01";
  const offset = Math.max(0, Number(body.offset) || 0);
  const limit = Math.min(5000, Math.max(1, Number(body.limit) || 3000));

  const { data, error } = await sb.rpc("compras_hq_export", { p_desde: desde, p_offset: offset, p_limit: limit });
  if (error) return json({ error: error.message }, 500);
  return json({ lineas: data ?? [], offset, limit });
});
