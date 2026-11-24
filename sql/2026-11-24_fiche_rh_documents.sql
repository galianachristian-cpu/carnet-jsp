-- Fiche RH : pièces jointes des JSP (pièce d'identité, certificats, attestations…).
-- Documents personnels (parfois médicaux) de mineurs : PAS dans un espace de stockage public.
-- Table fermée (RLS sans politique) : lecture/écriture uniquement via les fonctions ci-dessous,
-- réservées à l'admin et aux comptes spéciaux ayant l'accès « fiche-rh ». Jamais visibles des familles.
create table if not exists carnet_docs_rh (
  id uuid primary key default gen_random_uuid(),
  jsp_id bigint not null,
  type text not null default 'autre',
  nom text not null,
  mime text not null,
  taille int not null,
  contenu bytea not null,
  ajoute_le timestamptz not null default now(),
  ajoute_par text
);
create index if not exists carnet_docs_rh_jsp on carnet_docs_rh(jsp_id);
alter table carnet_docs_rh enable row level security;
revoke all on carnet_docs_rh from anon, authenticated;

-- Contrôle d'accès commun : renvoie l'utilisateur, ou null si refusé
create or replace function carnet_docs_rh_acces(p_login text, p_pass text, p_purge boolean default false)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare u jsonb;
begin
  begin u := carnet_verifier(p_login, p_pass);
  exception when sqlstate 'P0001' then return null; end;
  if u is null then return null; end if;
  if u->>'role' = 'admin' or coalesce((u->'acces'->>'fiche-rh')::boolean, false)
     or (p_purge and coalesce((u->'acces'->>'jsps')::boolean, false)) then return u; end if;
  return null;
end $$;
revoke execute on function carnet_docs_rh_acces(text, text, boolean) from public, anon, authenticated;

create or replace function carnet_docs_rh_liste(p_login text, p_pass text, p_jsp bigint default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
begin
  if carnet_docs_rh_acces(p_login, p_pass) is null then return jsonb_build_object('ok', false, 'erreur', 'acces'); end if;
  return jsonb_build_object('ok', true, 'docs', (select coalesce(jsonb_agg(jsonb_build_object(
      'id', id, 'jsp', jsp_id, 'type', type, 'nom', nom, 'mime', mime, 'taille', taille, 'le', ajoute_le, 'par', ajoute_par)
      order by ajoute_le desc), '[]'::jsonb)
    from carnet_docs_rh where p_jsp is null or jsp_id = p_jsp));
end $$;

create or replace function carnet_docs_rh_ajouter(p_login text, p_pass text, p_jsp bigint, p_type text, p_nom text, p_mime text, p_b64 text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare u jsonb; b bytea; nid uuid;
begin
  u := carnet_docs_rh_acces(p_login, p_pass);
  if u is null then return jsonb_build_object('ok', false, 'erreur', 'acces'); end if;
  if p_mime not in ('application/pdf', 'image/jpeg', 'image/png', 'image/webp') then
    return jsonb_build_object('ok', false, 'erreur', 'format'); end if;
  b := decode(p_b64, 'base64');
  if octet_length(b) > 5 * 1024 * 1024 then return jsonb_build_object('ok', false, 'erreur', 'taille'); end if;
  if (select count(*) from carnet_docs_rh where jsp_id = p_jsp) >= 40 then
    return jsonb_build_object('ok', false, 'erreur', 'trop'); end if;
  insert into carnet_docs_rh(jsp_id, type, nom, mime, taille, contenu, ajoute_par)
  values (p_jsp, left(coalesce(nullif(p_type, ''), 'autre'), 40), left(coalesce(nullif(p_nom, ''), 'document'), 150), p_mime, octet_length(b), b, u->>'login')
  returning id into nid;
  return jsonb_build_object('ok', true, 'id', nid);
end $$;

create or replace function carnet_docs_rh_lire(p_login text, p_pass text, p_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r carnet_docs_rh;
begin
  if carnet_docs_rh_acces(p_login, p_pass) is null then return jsonb_build_object('ok', false, 'erreur', 'acces'); end if;
  select * into r from carnet_docs_rh where id = p_id;
  if r.id is null then return jsonb_build_object('ok', false, 'erreur', 'introuvable'); end if;
  return jsonb_build_object('ok', true, 'nom', r.nom, 'mime', r.mime, 'b64', encode(r.contenu, 'base64'));
end $$;

create or replace function carnet_docs_rh_modifier(p_login text, p_pass text, p_id uuid, p_type text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
begin
  if carnet_docs_rh_acces(p_login, p_pass) is null then return jsonb_build_object('ok', false, 'erreur', 'acces'); end if;
  update carnet_docs_rh set type = left(coalesce(nullif(p_type, ''), 'autre'), 40) where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function carnet_docs_rh_supprimer(p_login text, p_pass text, p_id uuid)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
begin
  if carnet_docs_rh_acces(p_login, p_pass) is null then return jsonb_build_object('ok', false, 'erreur', 'acces'); end if;
  delete from carnet_docs_rh where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

-- Départ d'un JSP : ses documents sont effacés avec sa fiche
create or replace function carnet_docs_rh_purger(p_login text, p_pass text, p_jsp bigint)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare n int;
begin
  if carnet_docs_rh_acces(p_login, p_pass, true) is null then return jsonb_build_object('ok', false, 'erreur', 'acces'); end if;
  delete from carnet_docs_rh where jsp_id = p_jsp;
  get diagnostics n = row_count;
  return jsonb_build_object('ok', true, 'supprimes', n);
end $$;

-- Retour arrière :
-- drop function carnet_docs_rh_purger(text,text,bigint), carnet_docs_rh_supprimer(text,text,uuid), carnet_docs_rh_modifier(text,text,uuid,text),
--   carnet_docs_rh_lire(text,text,uuid), carnet_docs_rh_ajouter(text,text,bigint,text,text,text,text), carnet_docs_rh_liste(text,text,bigint),
--   carnet_docs_rh_acces(text,text,boolean);
-- drop table carnet_docs_rh;
