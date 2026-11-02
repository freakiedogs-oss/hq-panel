-- Compras HQ — sincronización de Freakie, Kaeru y Kako (mismo proyecto btbox)
-- Solo LEE public/kaeru/kako. Inserta líneas nuevas y refresca mapeo/anulación.

-- Monto sin IVA a partir del ítem del JSON del DTE ---------------------------------
-- FCF (01): ventaGravada trae IVA incluido → /1.13. CCF (03) y NC (05): sin IVA.
-- FSE (14): campo "compra". Sin JSON: se usa el monto de la línea.
create or replace function compras_hq._sin_iva(p_tipo text, p_item jsonb, p_monto numeric)
returns numeric language sql immutable set search_path to 'pg_temp' as $$
  select case
    when p_item is null then case when p_tipo = '01' then p_monto / 1.13 else p_monto end
    when p_item ? 'compra' and not (p_item ? 'ventaGravada') then coalesce((p_item->>'compra')::numeric, 0)
    else coalesce((p_item->>'ventaGravada')::numeric, 0) / case when p_tipo = '01' then 1.13 else 1 end
       + coalesce((p_item->>'ventaExenta')::numeric, 0)
       + coalesce((p_item->>'ventaNoSuj')::numeric, 0)
  end
$$;

create or replace function compras_hq._nit(p text)
returns text language sql immutable set search_path to 'pg_temp' as $$
  select nullif(regexp_replace(coalesce(p, ''), '\D', '', 'g'), '')
$$;

create or replace function compras_hq.sync_local()
returns jsonb
language plpgsql
security definer
set search_path to 'compras_hq', 'public', 'pg_temp'
as $$
declare v_f int; v_b int; v_ka int; v_ko int; v_upd int;
begin
  -- Freakie: líneas extraídas de los DTE de compra
  insert into compras_hq.linea (empresa, fuente, fuente_id, documento_id, fecha, tipo_dte,
         proveedor_nit, proveedor_nombre, descripcion, descripcion_norm, cantidad, unidad,
         precio_unitario, monto, monto_sin_iva, producto_ref, producto_nombre, anulada)
  select 'freakie', 'dte', i.id::text, d.id::text, d.fecha_emision,
         coalesce(d.json_original->'identificacion'->>'tipoDte', d.tipo_dte),
         compras_hq._nit(d.proveedor_nit), d.proveedor_nombre,
         i.descripcion_original, public.norm_desc(i.descripcion_original),
         i.cantidad, e.x->>'uniMedida', i.precio_unitario, i.monto_linea,
         compras_hq._sin_iva(coalesce(d.json_original->'identificacion'->>'tipoDte', d.tipo_dte), e.x, i.monto_linea),
         i.producto_id::text, cp.nombre, coalesce(d.invalidado, false)
  from public.compras_dte_items i
  join public.compras_dte d on d.id = i.compras_dte_id
  left join public.catalogo_productos cp on cp.id = i.producto_id
  left join lateral (
    select x from jsonb_array_elements(coalesce(d.json_original->'cuerpoDocumento', '[]'::jsonb))
           with ordinality t(x, n) where t.n = i.linea) e on true
  where d.fecha_emision is not null
  on conflict (empresa, fuente, fuente_id) do nothing;
  get diagnostics v_f = row_count;

  -- Freakie: pedidos BEES (La Constancia). El total de línea trae IVA.
  insert into compras_hq.linea (empresa, fuente, fuente_id, documento_id, fecha, tipo_dte,
         proveedor_nit, proveedor_nombre, descripcion, descripcion_norm, cantidad, unidad,
         precio_unitario, monto, monto_sin_iva, producto_ref, producto_nombre)
  select 'freakie', 'bees', i.id::text, b.id::text, b.fecha, '01',
         'BEES', coalesce(b.proveedor_nombre, 'LA CONSTANCIA (BEES)'),
         coalesce(i.descripcion, '') || coalesce(' · ' || i.empaque, ''),
         public.norm_desc(coalesce(i.descripcion, '') || coalesce(' · ' || i.empaque, '')),
         i.cantidad, '59', i.precio_unitario, i.total, i.total / 1.13,
         i.producto_id::text, cp.nombre
  from public.compras_bees_items i
  join public.compras_bees b on b.id = i.compra_bees_id
  left join public.catalogo_productos cp on cp.id = i.producto_id
  where b.fecha is not null
  on conflict (empresa, fuente, fuente_id) do nothing;
  get diagnostics v_b = row_count;

  -- Kaeru
  insert into compras_hq.linea (empresa, fuente, fuente_id, documento_id, fecha, tipo_dte,
         proveedor_nit, proveedor_nombre, descripcion, descripcion_norm, cantidad, unidad,
         precio_unitario, monto, monto_sin_iva, producto_ref, producto_nombre)
  select 'kaeru', 'dte', d.id::text, c.id::text, c.fecha_emision,
         coalesce(c.json_dte->'identificacion'->>'tipoDte', c.tipo_dte),
         compras_hq._nit(coalesce(c.emisor_nit, c.json_dte->'emisor'->>'nit')), c.emisor_nombre,
         d.descripcion, public.norm_desc(d.descripcion), d.cantidad, d.unidad,
         d.precio_unitario, d.monto,
         compras_hq._sin_iva(coalesce(c.json_dte->'identificacion'->>'tipoDte', c.tipo_dte), e.x, d.monto),
         d.ingrediente_id::text, ig.nombre
  from kaeru.compras_dte_detalle d
  join kaeru.compras_dte c on c.id = d.compra_dte_id
  left join kaeru.ingredientes ig on ig.id = d.ingrediente_id
  left join lateral (
    select x from jsonb_array_elements(coalesce(c.json_dte->'cuerpoDocumento', '[]'::jsonb))
           with ordinality t(x, n) where t.n = d.orden) e on true
  where c.fecha_emision is not null
  on conflict (empresa, fuente, fuente_id) do nothing;
  get diagnostics v_ka = row_count;

  -- Kako
  insert into compras_hq.linea (empresa, fuente, fuente_id, documento_id, fecha, tipo_dte,
         proveedor_nit, proveedor_nombre, descripcion, descripcion_norm, cantidad, unidad,
         precio_unitario, monto, monto_sin_iva, producto_ref, producto_nombre)
  select 'kako', 'dte', d.id::text, c.id::text, c.fecha_emision,
         coalesce(c.json_dte->'identificacion'->>'tipoDte', c.tipo_dte),
         compras_hq._nit(coalesce(c.emisor_nit, c.json_dte->'emisor'->>'nit')), c.emisor_nombre,
         d.descripcion, public.norm_desc(d.descripcion), d.cantidad, d.unidad,
         d.precio_unitario, d.monto,
         compras_hq._sin_iva(coalesce(c.json_dte->'identificacion'->>'tipoDte', c.tipo_dte), e.x, d.monto),
         d.ingrediente_id::text, ig.nombre
  from kako.compras_dte_detalle d
  join kako.compras_dte c on c.id = d.compra_dte_id
  left join kako.ingredientes ig on ig.id = d.ingrediente_id
  left join lateral (
    select x from jsonb_array_elements(coalesce(c.json_dte->'cuerpoDocumento', '[]'::jsonb))
           with ordinality t(x, n) where t.n = d.orden) e on true
  where c.fecha_emision is not null
  on conflict (empresa, fuente, fuente_id) do nothing;
  get diagnostics v_ko = row_count;

  -- Refrescar lo que cambia después: mapeo a producto del ERP y anulación (Freakie)
  update compras_hq.linea l
     set producto_ref = i.producto_id::text, producto_nombre = cp.nombre,
         anulada = coalesce(d.invalidado, false)
    from public.compras_dte_items i
    join public.compras_dte d on d.id = i.compras_dte_id
    left join public.catalogo_productos cp on cp.id = i.producto_id
   where l.empresa = 'freakie' and l.fuente = 'dte' and l.fuente_id = i.id::text
     and (l.producto_ref is distinct from i.producto_id::text
          or l.anulada is distinct from coalesce(d.invalidado, false));
  get diagnostics v_upd = row_count;

  -- Proveedores nuevos (uno por NIT, nombre más reciente)
  insert into compras_hq.proveedor (nit, nombre, nombres)
  select proveedor_nit, (array_agg(proveedor_nombre order by fecha desc))[1],
         array_agg(distinct proveedor_nombre)
  from compras_hq.linea
  where proveedor_nit is not null and proveedor_nombre is not null
  group by proveedor_nit
  on conflict (nit) do nothing;

  return jsonb_build_object('freakie_dte', v_f, 'freakie_bees', v_b, 'kaeru', v_ka, 'kako', v_ko,
                            'actualizadas', v_upd);
end;
$$;
