# memoria.md — hq-panel

> Bitácora de decisiones y cambios, **lo más nuevo arriba**. Escribí corto y con el *por qué*, no solo el qué.

---

## 2026-08-18 — Se crea esta memoria (y por qué faltaba)

`hq-panel` era el único de los 8 repos **sin `CLAUDE.md` ni `memoria.md`**. Consecuencia real: una sesión de Claude que arrancó acá no tenía ritual ni contexto y tuvo que reconstruir todo desde `git log` y transcripts viejos.

Se creó junto con el rediseño del remote-control de la mini (ver `~/.claude/CLAUDE.md` y `~/Proyectos/server/bin/rc_supervisor.sh`). — *Jose + Claude, 18-ago-2026*

---

## Historial previo (reconstruido desde `git log`)

- **2026-08-09** `0a97fbf` — Banner honesto cuando el backend bloquea re-decidir (`ya_decidida`). *Criterio: el panel no simula éxito; si el backend dice que no, se muestra.*
- **2026-08-09** `5b1c66f` — Enlace venture↔idea por `idea_id`, con fallback a nombre.
- **2026-08-09** `6e43311` — Cada venture con desplegable: análisis del lab + plan a mercado + historial de eventos.
- **2026-08-09** `9e15349` — **Parseo robusto de timestamps** (Postgres nativo + ISO) para evitar `Invalid Date` y desfase horario **en Safari/iPhone**. *Es el bug recurrente de este panel: Safari es estricto con formatos de fecha que Chrome perdona.*
- **2026-08-08** `5b4a1d8` — Lab de ideas: un solo listado ordenado por % de éxito, todas expandibles y gestionables.
- **2026-08-01** `ad961ef` — Nace el panel: estático, datos vía edge function `factory-dashboard` con token.

---

## Cosas que conviene no volver a aprender por las malas

- **Safari/iOS es el navegador de verdad acá**, no Chrome. Fechas y layout se validan ahí.
- El panel **no** habla con Supabase directo: todo pasa por `factory-dashboard`. Si falta un dato, el fix suele ir en la edge function (repo `venture-factory`), no en el HTML.
- No hay build: lo que ves en `index.html` es lo que se sirve.
