// compras-gateway — proyecto btboxlwfqcbrdfrlnwln
// Un solo gateway para Compras HQ. El token (?t=) decide qué se ve: una empresa o HQ.
// La base recibe solo el SHA-256 del token (tabla compras_hq.acceso).
//   GET/POST ?t=<token>&accion=resumen|comparativo|item|revision|confirmar
//   params opcionales: empresa (solo HQ), item_id, alias_id, estado, base_por_unidad
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const ORIGENES = ["https://freakiedogs-oss.github.io", "http://localhost:8000", "http://127.0.0.1:8000"];
const ACCIONES = new Set(["resumen", "comparativo", "item", "revision", "confirmar"]);

function cors(req: Request) {
  const o = req.headers.get("origin") ?? "";
  return {
    "Access-Control-Allow-Origin": ORIGENES.includes(o) ? o : ORIGENES[0],
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "content-type",
    "Vary": "Origin",
  };
}

async function sha256(s: string) {
  const b = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req) => {
  const h = { ...cors(req), "Content-Type": "application/json", "Cache-Control": "no-store" };
  if (req.method === "OPTIONS") return new Response(null, { headers: h });

  const url = new URL(req.url);
  const body = req.method === "POST" ? await req.json().catch(() => ({})) : {};
  const q = (k: string) => (body[k] ?? url.searchParams.get(k) ?? "") as string;

  const token = q("t");
  const accion = q("accion") || "resumen";
  if (!/^[a-f0-9]{48}$/.test(token)) return new Response(JSON.stringify({ error: "no_autorizado" }), { status: 401, headers: h });
  if (!ACCIONES.has(accion)) return new Response(JSON.stringify({ error: "accion_desconocida" }), { status: 400, headers: h });
  if (accion === "confirmar" && req.method !== "POST") {
    return new Response(JSON.stringify({ error: "usar POST" }), { status: 405, headers: h });
  }

  const params: Record<string, string> = {};
  for (const k of ["empresa", "item_id", "alias_id", "estado", "base_por_unidad"]) {
    const v = q(k);
    if (v !== "") params[k] = String(v).slice(0, 64);
  }

  const { data, error } = await sb.rpc("compras_hq_gateway", {
    p_token_hash: await sha256(token), p_accion: accion, p_params: params,
  });
  if (error) return new Response(JSON.stringify({ error: "interno", detalle: error.message }), { status: 500, headers: h });
  const status = data?.error === "no_autorizado" ? 401 : data?.error ? 400 : 200;
  return new Response(JSON.stringify(data), { status, headers: h });
});
