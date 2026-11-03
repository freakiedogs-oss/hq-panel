// compras-hq-sync — proyecto btboxlwfqcbrdfrlnwln
// 1) compras_hq.sync_local(): Freakie (DTE + BEES), Kaeru y Kako, mismo proyecto.
// 2) Trae Eatalia y Scanzano desde la edge fn `compras-export` (wzk) y las ingesta.
// Idempotente: se puede llamar cuantas veces se quiera. Por defecto refresca 120 días;
// con {"desde":"2022-01-01"} hace la carga completa.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const sb = createClient(Deno.env.get("SUPABASE_URL")!, SERVICE_KEY);
const EXPORT_URL = "https://wzkqaxgsqgbokkmxarbd.supabase.co/functions/v1/compras-export";
const PAGINA = 3000;

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  const t0 = Date.now();
  const body = await req.json().catch(() => ({}));
  const hace120 = new Date(Date.now() - 120 * 864e5).toISOString().slice(0, 10);

  // Sin la llave de servicio (p. ej. el cron): solo incremental y máximo cada 10 min.
  const esServicio = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "") === SERVICE_KEY;
  if (!esServicio) {
    const rec = await sb.rpc("compras_hq_sync_reciente", { p_minutos: 10 });
    if (rec.data === true) return json({ ok: true, omitido: "corrió hace menos de 10 min" });
  }
  // Primera corrida (sin líneas remotas todavía): histórico completo.
  const hay = await sb.rpc("compras_hq_hay_remotas");
  const desde = esServicio && /^\d{4}-\d{2}-\d{2}$/.test(body.desde ?? "")
    ? body.desde
    : hay.data === false ? "2022-01-01" : hace120;

  const local = await sb.rpc("compras_hq_sync_local");
  if (local.error) return json({ etapa: "local", error: local.error.message }, 500);

  let remotas = 0, paginas = 0;
  for (let offset = 0; ; offset += PAGINA) {
    const r = await fetch(EXPORT_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-hq-key": SERVICE_KEY },
      body: JSON.stringify({ desde, offset, limit: PAGINA }),
    });
    if (!r.ok) return json({ etapa: "export", status: r.status, error: await r.text(), local: local.data }, 502);
    const { lineas } = await r.json();
    if (!Array.isArray(lineas) || lineas.length === 0) break;
    const ing = await sb.rpc("compras_hq_ingestar", { p_lineas: lineas });
    if (ing.error) return json({ etapa: "ingestar", offset, error: ing.error.message }, 500);
    remotas += lineas.length;
    paginas++;
    if (lineas.length < PAGINA) break;
  }

  const ref = await sb.rpc("compras_hq_refrescar");
  const resultado = { ok: true, desde, local: local.data, remotas, paginas, refresco: ref.error ? ref.error.message : "ok", ms: Date.now() - t0 };
  await sb.rpc("compras_hq_log_sync", { p_origen: esServicio ? "servicio" : "cron", p_resultado: resultado });
  return json(resultado);
});
