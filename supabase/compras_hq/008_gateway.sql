-- Compras HQ — gateway único con vistas independientes por empresa
-- El token viaja en el link (?t=); a la base solo llega su SHA-256. empresa null = HQ (todo).

create table if not exists compras_hq.acceso (
  token_hash  text primary key,           -- sha256 hex del token
  empresa     text references compras_hq.empresa(id),   -- null = HQ
  nombre      text not null,
  activo      boolean not null default true,
  created_at  timestamptz not null default now(),
  ultimo_uso  timestamptz
);
alter table compras_hq.acceso enable row level security;

create or replace function public.compras_hq_gateway(p_token_hash text, p_accion text, p_params jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'compras_hq', 'public', 'pg_temp'
as $$
declare
  v_acc compras_hq.acceso;
  v_emp text;          -- empresa del token (null = HQ)
  v_filtro text;       -- empresa a mostrar
  v_hq boolean;
  v jsonb;
begin
  if not compras_hq._es_servicio() then raise exception 'solo service_role'; end if;

  select * into v_acc from compras_hq.acceso where token_hash = p_token_hash and activo;
  if not found then return jsonb_build_object('error', 'no_autorizado'); end if;
  perform compras_hq._tocar_acceso(p_token_hash);

  v_emp := v_acc.empresa;
  v_hq := v_emp is null;
  -- HQ puede elegir empresa; una empresa solo se ve a sí misma
  v_filtro := case when v_hq then nullif(p_params->>'empresa', '') else v_emp end;

  if p_accion = 'resumen' then
    select jsonb_build_object(
      'acceso', jsonb_build_object('nombre', v_acc.nombre, 'hq', v_hq, 'empresa', v_emp),
      'empresas', (select jsonb_agg(jsonb_build_object('id', id, 'nombre', nombre) order by id)
                   from compras_hq.empresa where v_hq or id = v_emp),
      'filtro', v_filtro,
      'kpi', (
        with l as (
          select l.monto_sin_iva m, a.id is not null mapeado
          from compras_hq.linea l
          left join compras_hq.proveedor p on p.nit = l.proveedor_key
          left join compras_hq.alias a on a.proveedor_nit = l.proveedor_key and a.descripcion_norm = l.descripcion_norm
          where not l.anulada and l.fecha >= current_date - 90 and coalesce(l.tipo_dte, '') not in ('05','06')
            and l.monto_sin_iva > 0 and not coalesce(p.excluir_comparacion, false)
            and (v_filtro is null or l.empresa = v_filtro)
        )
        select jsonb_build_object(
          'gasto_insumos_90d', round(coalesce(sum(m), 0), 2),
          'pct_mapeado', round(100 * coalesce(sum(m) filter (where mapeado), 0) / nullif(sum(m), 0)),
          'ahorro_90d', (select round(coalesce(sum(ahorro_90d), 0), 2) from compras_hq.v_ahorro
                         where proveedores_item > 1 and ahorro_90d > 0 and (v_filtro is null or empresa = v_filtro)),
          'alertas', (select count(*) from compras_hq.v_alerta_precio where v_filtro is null or empresa = v_filtro),
          'ultima_sync', (select max(at) from compras_hq.sync_log))
        from l),
      'ahorro', coalesce((select jsonb_agg(to_jsonb(x) order by x.ahorro_90d desc) from (
          select case when v_hq then empresa end empresa, item_id, item, categoria, unidad_base,
                 round(gasto_90d, 2) gasto_90d, round(precio_pagado_90d, 4) precio_pagado,
                 round(mejor_precio, 4) mejor_precio, mejor_proveedor, sobreprecio_pct, round(ahorro_90d, 2) ahorro_90d
          from compras_hq.v_ahorro
          where proveedores_item > 1 and ahorro_90d > 0 and (v_filtro is null or empresa = v_filtro)
          order by ahorro_90d desc limit 40) x), '[]'::jsonb),
      'alertas', coalesce((select jsonb_agg(to_jsonb(x) order by x.alza_pct desc) from (
          select case when v_hq then empresa end empresa, item_id, item, unidad_base, proveedor, ultima_compra,
                 round(ultimo_precio, 4) ultimo_precio, round(precio_mediano_90d, 4) mediana_90d, alza_pct
          from compras_hq.v_alerta_precio where v_filtro is null or empresa = v_filtro
          order by alza_pct desc limit 40) x), '[]'::jsonb)
    ) into v;
    return v;

  elsif p_accion = 'comparativo' then
    -- items que la empresa compra, con sus proveedores; el "mejor del grupo" se muestra como
    -- referencia (proveedor y precio) sin decir qué empresa lo paga
    select coalesce(jsonb_agg(to_jsonb(x) order by x.gasto_item desc, x.item, x.precio), '[]'::jsonb) into v from (
      with mis as (
        select ip.item_id, ip.item, ip.categoria, ip.unidad_base, ip.proveedor_key, max(ip.proveedor) proveedor,
               string_agg(distinct ip.empresa, ',') empresas,
               sum(ip.gasto_12m) gasto_12m,
               min(coalesce(ip.precio_mediano_90d, ip.precio_mediano_12m)) precio,
               max(ip.ultima_compra) ultima_compra
        from compras_hq.v_item_proveedor ip
        where v_filtro is null or ip.empresa = v_filtro
        group by 1,2,3,4,5
      ), grupo as (select distinct item_id, mejor_precio, mejor_proveedor from compras_hq.v_comparativo)
      select m.item_id, m.item, m.categoria, m.unidad_base, m.proveedor,
             case when v_hq then m.empresas end empresas,
             round(m.gasto_12m, 2) gasto_12m, round(m.precio, 4) precio, m.ultima_compra,
             round(g.mejor_precio, 4) mejor_grupo, g.mejor_proveedor mejor_proveedor_grupo,
             round(100 * (m.precio / nullif(g.mejor_precio, 0) - 1), 1) dif_pct,
             sum(m.gasto_12m) over (partition by m.item_id) gasto_item,
             count(*) over (partition by m.item_id) proveedores
      from mis m join grupo g using (item_id)
    ) x
    where x.proveedores > 1 or x.dif_pct > 0.5;
    return jsonb_build_object('items', v);

  elsif p_accion = 'item' then
    -- historia mensual de precio del item por proveedor (solo la empresa del token, o todas en HQ)
    select coalesce(jsonb_agg(to_jsonb(x) order by x.mes, x.proveedor), '[]'::jsonb) into v from (
      select to_char(date_trunc('month', fecha), 'YYYY-MM') mes, proveedor,
             case when v_hq then string_agg(distinct empresa, ',') end empresas,
             round((percentile_cont(0.5) within group (order by precio_base))::numeric, 4) precio,
             round(sum(cantidad_base), 2) cantidad
      from compras_hq.mv_precio v
      where v.item_id = (p_params->>'item_id')::bigint and v.base_por_unidad is not null
        and v.fecha >= current_date - 365 and (v_filtro is null or v.empresa = v_filtro)
        and not v.atipico
      group by 1, 2) x;
    return jsonb_build_object('historia', v);

  elsif p_accion = 'revision' then
    if not v_hq then return jsonb_build_object('error', 'solo_hq'); end if;
    select coalesce(jsonb_agg(to_jsonb(x) order by x.gasto_12m desc nulls last), '[]'::jsonb) into v from (
      select a.id alias_id, a.proveedor_nit, coalesce(p.nombre, a.proveedor_nit) proveedor, a.descripcion_norm descripcion,
             i.id item_id, i.nombre item, i.unidad_base, a.base_por_unidad, a.estado, a.notas,
             (select round(sum(l.monto_sin_iva), 2) from compras_hq.linea l
               where l.proveedor_key = a.proveedor_nit and l.descripcion_norm = a.descripcion_norm
                 and l.fecha >= current_date - 365 and not l.anulada) gasto_12m,
             (select mode() within group (order by l.unidad) from compras_hq.linea l
               where l.proveedor_key = a.proveedor_nit and l.descripcion_norm = a.descripcion_norm) unidad_factura
      from compras_hq.alias a
      join compras_hq.item i on i.id = a.item_id
      left join compras_hq.proveedor p on p.nit = a.proveedor_nit
      where a.estado = 'propuesto'
      limit 300) x;
    return jsonb_build_object('alias', v);

  elsif p_accion = 'confirmar' then
    if not v_hq then return jsonb_build_object('error', 'solo_hq'); end if;
    return compras_hq._confirmar_alias((p_params->>'alias_id')::bigint, p_params->>'estado',
                                       nullif(p_params->>'base_por_unidad', '')::numeric, v_acc.nombre);
  end if;

  return jsonb_build_object('error', 'accion_desconocida');
end;
$$;

create or replace function compras_hq._tocar_acceso(p_hash text)
returns void language sql security definer set search_path to 'compras_hq', 'pg_temp' as $$
  update compras_hq.acceso set ultimo_uso = now() where token_hash = p_hash
$$;

create or replace function compras_hq._confirmar_alias(p_id bigint, p_estado text, p_base numeric, p_quien text)
returns jsonb language plpgsql security definer set search_path to 'compras_hq', 'pg_temp' as $$
begin
  if p_estado not in ('confirmado', 'rechazado', 'propuesto') then
    return jsonb_build_object('error', 'estado_invalido');
  end if;
  if p_base is not null and p_base <= 0 then return jsonb_build_object('error', 'base_invalida'); end if;
  update compras_hq.alias
     set estado = p_estado, base_por_unidad = coalesce(p_base, base_por_unidad),
         origen = case when p_base is not null then 'manual' else origen end,
         notas = trim(coalesce(notas, '') || ' · ' || p_estado || ' por ' || p_quien || ' ' || to_char(now(), 'DD-MM-YYYY')),
         updated_at = now()
   where id = p_id;
  if not found then return jsonb_build_object('error', 'no_existe'); end if;
  perform compras_hq.refrescar();   -- que el panel vea el cambio al instante
  return jsonb_build_object('ok', true, 'alias_id', p_id, 'estado', p_estado);
end;
$$;

-- Alta de accesos: recibe solo hashes (los tokens viven en la mini, en ~/.config/compras-hq/)
create or replace function compras_hq.registrar_acceso(p_hash text, p_empresa text, p_nombre text)
returns void language sql security definer set search_path to 'compras_hq', 'pg_temp' as $$
  insert into compras_hq.acceso (token_hash, empresa, nombre) values (p_hash, p_empresa, p_nombre)
  on conflict (token_hash) do nothing
$$;
