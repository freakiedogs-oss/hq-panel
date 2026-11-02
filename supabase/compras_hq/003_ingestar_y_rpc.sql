-- Compras HQ — ingesta de líneas remotas (Eatalia/Scanzano) y RPCs públicas
-- Las RPCs public.compras_hq_* validan service_role: anon/authenticated no pasan.

create or replace function compras_hq._es_servicio()
returns boolean language sql stable set search_path to 'pg_temp' as $$
  -- en SECURITY DEFINER current_user es el dueño; session_user es quien conectó
  select coalesce(auth.role(), '') = 'service_role' or session_user in ('postgres', 'supabase_admin')
$$;

create or replace function compras_hq.ingestar(p_lineas jsonb)
returns integer
language plpgsql
security definer
set search_path to 'compras_hq', 'public', 'pg_temp'
as $$
declare v_n int;
begin
  insert into compras_hq.linea (empresa, fuente, fuente_id, documento_id, fecha, tipo_dte,
         proveedor_nit, proveedor_nombre, descripcion, descripcion_norm, cantidad, unidad,
         precio_unitario, monto, monto_sin_iva, producto_ref, producto_nombre, anulada)
  select r.empresa, r.fuente, r.fuente_id, r.documento_id, r.fecha, r.tipo_dte,
         r.proveedor_nit, r.proveedor_nombre, r.descripcion, public.norm_desc(r.descripcion),
         r.cantidad, lower(r.unidad), r.precio_unitario, r.monto, r.monto_sin_iva,
         r.producto_ref, r.producto_nombre, coalesce(r.anulada, false)
  from jsonb_to_recordset(p_lineas) as r(
         empresa text, fuente text, fuente_id text, documento_id text, fecha date, tipo_dte text,
         proveedor_nit text, proveedor_nombre text, descripcion text, cantidad numeric, unidad text,
         precio_unitario numeric, monto numeric, monto_sin_iva numeric, producto_ref text,
         producto_nombre text, anulada boolean)
  where r.empresa in ('eatalia', 'scanzano') and r.fecha is not null and r.descripcion is not null
  on conflict (empresa, fuente, fuente_id) do update
     set fecha = excluded.fecha, tipo_dte = excluded.tipo_dte,
         proveedor_nit = excluded.proveedor_nit, proveedor_nombre = excluded.proveedor_nombre,
         descripcion = excluded.descripcion, descripcion_norm = excluded.descripcion_norm,
         cantidad = excluded.cantidad, unidad = excluded.unidad,
         precio_unitario = excluded.precio_unitario, monto = excluded.monto,
         monto_sin_iva = excluded.monto_sin_iva, producto_ref = excluded.producto_ref,
         producto_nombre = excluded.producto_nombre, anulada = excluded.anulada;
  get diagnostics v_n = row_count;

  insert into compras_hq.proveedor (nit, nombre, nombres)
  select proveedor_nit, (array_agg(proveedor_nombre order by fecha desc))[1], array_agg(distinct proveedor_nombre)
  from compras_hq.linea
  where empresa in ('eatalia', 'scanzano') and proveedor_nit is not null and proveedor_nombre is not null
  group by proveedor_nit
  on conflict (nit) do nothing;
  return v_n;
end;
$$;

-- RPCs públicas (las usan las edge functions con service_role) ---------------------
create or replace function public.compras_hq_autorizar_export()
returns boolean language plpgsql stable security definer set search_path to 'pg_temp' as $$
begin
  -- Eatalia llama aquí con la llave que recibió: si es service_role de btbox, autoriza
  return coalesce(auth.role(), '') = 'service_role';
end;
$$;

create or replace function public.compras_hq_sync_local()
returns jsonb language plpgsql security definer set search_path to 'compras_hq', 'public', 'pg_temp' as $$
begin
  if not compras_hq._es_servicio() then raise exception 'solo service_role'; end if;
  return compras_hq.sync_local();
end;
$$;

create or replace function public.compras_hq_ingestar(p_lineas jsonb)
returns integer language plpgsql security definer set search_path to 'compras_hq', 'public', 'pg_temp' as $$
begin
  if not compras_hq._es_servicio() then raise exception 'solo service_role'; end if;
  return compras_hq.ingestar(p_lineas);
end;
$$;
