-- Compras HQ — exportación de líneas de compra de Eatalia y Scanzano
-- Proyecto: wzkqaxgsqgbokkmxarbd. SOLO LECTURA de compras_eatalia, compras_items_eatalia,
-- compras_scanzano y materias_primas. La llama la edge fn `compras-export` con service_role.
--
-- monto_sin_iva:
--   Eatalia → prorrateo contra el resumen del DTE (totalGravada/1.13 en FCF + exenta + no
--   sujeta), porque en FCF el subtotal de línea a veces trae IVA y a veces no.
--   Sin DTE: CCF/NC tal cual; FCF /1.13 solo si las líneas suman el total con IVA.
--   Scanzano → subtotal de la fila (la tabla trae iva aparte).

create or replace function public.compras_hq_export(p_desde date, p_offset int default 0, p_limit int default 3000)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public', 'pg_temp'
as $$
declare v jsonb;
begin
  -- ojo: en SECURITY DEFINER current_user es el dueño; session_user es quien conectó
  if coalesce(auth.role(), '') <> 'service_role' and session_user not in ('postgres', 'supabase_admin') then
    raise exception 'solo service_role';
  end if;

  with ec as (
    select c.id, c.fecha, c.estado, c.proveedor, c.subtotal, c.total, c.dte_json,
           coalesce(c.dte_json->'identificacion'->>'tipoDte',
                    case c.tipo_doc when 'ccf' then '03' when 'factura' then '01'
                                    when 'nota_credito' then '05' else c.tipo_doc end) tipo,
           nullif(regexp_replace(coalesce(c.dte_json->'emisor'->>'nit', ''), '\D', '', 'g'), '') nit,
           (select sum(i.subtotal) from compras_items_eatalia i where i.compra_id = c.id) suma_items
    from compras_eatalia c
    where c.fecha >= p_desde
  ), ef as (
    select ec.*,
      case
        when coalesce(ec.suma_items, 0) = 0 then 1
        when ec.dte_json ? 'resumen' then
          ( coalesce((ec.dte_json->'resumen'->>'totalGravada')::numeric, 0) / case when ec.tipo = '01' then 1.13 else 1 end
          + coalesce((ec.dte_json->'resumen'->>'totalExenta')::numeric, 0)
          + coalesce((ec.dte_json->'resumen'->>'totalNoSuj')::numeric, 0) ) / ec.suma_items
        when ec.tipo = '01' and abs(ec.suma_items - ec.total) < 0.05 then 1 / 1.13
        else 1
      end factor
    from ec
  ), lineas as (
    select 'eatalia' empresa, 'eatalia' fuente, i.id::text fuente_id, ef.id::text documento_id,
           ef.fecha, ef.tipo tipo_dte, ef.nit proveedor_nit, ef.proveedor proveedor_nombre,
           i.nombre_dte descripcion, i.cantidad, i.unidad, i.precio_unit precio_unitario,
           i.subtotal monto, round(i.subtotal * ef.factor, 4) monto_sin_iva,
           i.materia_prima_id::text producto_ref, mp.nombre producto_nombre,
           (ef.estado = 'anulado') anulada
    from compras_items_eatalia i
    join ef on ef.id = i.compra_id
    left join materias_primas mp on mp.id = i.materia_prima_id
    union all
    select 'scanzano', 'scanzano', s.id::text, coalesce(s.uuid_dte, s.correlativo_doc, s.id::text),
           s.fecha, coalesce(s.json_dte->'identificacion'->>'tipoDte', 'excel'),
           nullif(regexp_replace(coalesce(s.json_dte->'emisor'->>'nit', ''), '\D', '', 'g'), ''),
           s.proveedor_nombre, coalesce(s.item, '(sin descripción)'), s.cantidad, s.unidad,
           s.precio_unitario, s.subtotal, s.subtotal, s.materia_prima_id::text, null, false
    from compras_scanzano s
    where s.fecha >= p_desde
  )
  select coalesce(jsonb_agg(to_jsonb(l) order by l.fuente, l.fuente_id), '[]'::jsonb) into v
  from (select * from lineas order by fuente, fuente_id offset p_offset limit p_limit) l;
  return v;
end;
$$;
