# hq-panel — Instrucciones para Claude

> Panel HQ **del Venture Factory**: una sola página estática (`index.html`) que muestra ideas, ventures y su progreso en vivo. No es un ERP y no tiene build.

## Ritual de inicio
1. Leé este archivo.
2. Leé **`memoria.md`** (bitácora, lo más nuevo arriba).
3. Si la task toca la lógica de negocio (ideas, ventures, decisiones, scoring), el cerebro está en el repo hermano **`~/Proyectos/venture-factory`** — leé su `CLAUDE.md` + `memoria.md` (198 KB, leelo por secciones, no entero).

## Qué es y cómo funciona
- **Pantalla principal:** `index.html` (~21 KB). HTML + CSS + JS inline, sin framework, sin bundler, sin `node_modules`. Se edita directo.
- **Título:** "Venture Factory — Live".
- **Datos:** los trae de la edge function **`factory-dashboard`** (Supabase, `…supabase.co/functions/v1/factory-dashboard`) autenticada **por token**. El panel no habla con la DB directo.
- **Tema claro/oscuro:** por `prefers-color-scheme` + override manual con `:root[data-theme=...]`.
- **Repo:** github.com/freakiedogs-oss/hq-panel · branch `main`.

## Compras HQ (desde 3-nov-2026)
- **`compras.html`**: segunda pantalla, también estática. Habla con la edge function **`compras-gateway`** (proyecto btbox) con un token por empresa o de HQ en `?t=`. Ver `memoria.md` (entrada 2026-11-03).
- **`supabase/`**: SQL del schema `compras_hq` y código de las edge functions `compras-gateway`, `compras-hq-sync` (btbox) y `compras-export` (wzk). Se despliegan por MCP; este repo es la copia en git.
- **El repo es público** (GitHub Pages): nada de tokens, NIT de personas ni precios por proveedor en git. Las semillas de alias viven en `~/Proyectos/_auditorias/compras_hq_semillas/`.

## Convenciones
- **Es una pantalla que Jose mira desde el iPhone.** Safari/iOS es el target real: cuidá el parseo de fechas (ya hubo un bug de `Invalid Date` por timestamps de Postgres vs ISO — ver `memoria.md`) y que todo sea legible en pantalla chica.
- **Nunca inventes estado en la UI.** Si el backend bloquea una acción, el panel debe decirlo con honestidad (ej. el banner de `ya_decidida`), no simular que funcionó.
- Al terminar algo material: actualizá `memoria.md` (entrada nueva arriba), commit claro + `git push`.
- El token de la edge function **jamás** en git ni en logs.

## Remote control
Este repo tiene su propio puente de remote-control (`--name "HQ Panel"`), supervisado por `com.freakie.rc-supervisor`. Ver la sección de MCP/infra en `~/.claude/CLAUDE.md`.
