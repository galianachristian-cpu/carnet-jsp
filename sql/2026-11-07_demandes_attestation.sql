-- Demandes d'attestation par les familles.
-- Ajoute à carnet_fusion_famille (filtre des écritures des comptes famille) la prise en charge
-- de la liste « demandesAttestation », sur le modèle des demandes d'absence :
--   * une famille ne peut ajouter qu'une demande pour son propre enfant (jspId du compte) ;
--   * statut forcé à « en_attente » ; nom/prénom/promotion repris de la fiche ;
--   * champs texte tronqués ; maximum 30 demandes en attente par enfant ;
--   * une demande existante n'est jamais modifiée ni supprimée par une famille.
-- Le reste de la fonction est inchangé. Sauvegarde de l'ancienne version : voir
-- sql/sauvegarde_carnet_fusion_famille_avant_2026-11-07.sql

create or replace function public.carnet_fusion_famille(ancien jsonb, recu jsonb, u jsonb)
 returns jsonb
 language plpgsql
 immutable
 set search_path to 'public'
as $function$
declare
  moi text := u->>'jspId';
  promo text;
  jsp jsonb;
  r jsonb := ancien;
  x jsonb; a jsonb; m jsonb; i int; nid numeric;
  liste jsonb;
begin
  liste := '[]'::jsonb;
  if coalesce(moi, '') = '' then return jsonb_set(r, '{users}', coalesce(recu->'users', '[]')); end if;
  select x2 into jsp from jsonb_array_elements(coalesce(r->'jsps', '[]')) x2 where x2->>'id' = moi limit 1;
  promo := jsp->>'promotion';

  for x in select * from jsonb_array_elements(case when jsonb_typeof(recu->'demandesAbsence') = 'array' then recu->'demandesAbsence' else '[]' end) loop
    if x->>'jspId' = moi and x ? 'id'
       and not exists (select 1 from jsonb_array_elements(coalesce(r->'demandesAbsence', '[]')) y where y->>'id' = x->>'id') then
      x := x || jsonb_build_object('statut', 'en_attente', 'prenom', jsp->'prenom', 'nom', jsp->'nom', 'promotion', jsp->'promotion',
                                   'motif', left(coalesce(x->>'motif', ''), 100), 'commentaire', left(coalesce(x->>'commentaire', ''), 300));
      r := jsonb_set(r, '{demandesAbsence}', coalesce(r->'demandesAbsence', '[]') || jsonb_build_array(x));
    end if;
  end loop;

  -- NOUVEAU : demandes d'attestation
  for x in select * from jsonb_array_elements(case when jsonb_typeof(recu->'demandesAttestation') = 'array' then recu->'demandesAttestation' else '[]' end) loop
    if jsonb_typeof(x) = 'object' and x->>'jspId' = moi and x ? 'id'
       and not exists (select 1 from jsonb_array_elements(coalesce(r->'demandesAttestation', '[]')) y where y->>'id' = x->>'id')
       and (select count(*) from jsonb_array_elements(coalesce(r->'demandesAttestation', '[]')) y
             where y->>'jspId' = moi and y->>'statut' = 'en_attente') < 30 then
      x := jsonb_build_object('id', x->'id', 'jspId', x->'jspId', 'ts', x->'ts', 'statut', 'en_attente',
                              'prenom', jsp->'prenom', 'nom', jsp->'nom', 'promotion', jsp->'promotion',
                              'activite', left(coalesce(x->>'activite', ''), 120),
                              'date', left(coalesce(x->>'date', ''), 10),
                              'organisme', left(coalesce(x->>'organisme', ''), 120),
                              'commentaire', left(coalesce(x->>'commentaire', ''), 300));
      r := jsonb_set(r, '{demandesAttestation}', coalesce(r->'demandesAttestation', '[]') || jsonb_build_array(x));
    end if;
  end loop;

  for x in select * from jsonb_array_elements(case when jsonb_typeof(recu->'validationsReglement') = 'array' then recu->'validationsReglement' else '[]' end) loop
    if x->>'jspId' = moi
       and not exists (select 1 from jsonb_array_elements(coalesce(r->'validationsReglement', '[]')) y where y->>'jspId' = moi and y->>'version' is not distinct from x->>'version') then
      r := jsonb_set(r, '{validationsReglement}', coalesce(r->'validationsReglement', '[]') || jsonb_build_array(
        jsonb_build_object('jspId', x->'jspId', 'date', x->'date', 'login', u->'login', 'version', x->'version')));
    end if;
  end loop;

  for x in select * from jsonb_array_elements(case when jsonb_typeof(recu->'questionnaireReponses') = 'array' then recu->'questionnaireReponses' else '[]' end) loop
    if x->>'jspId' = moi
       and not exists (select 1 from jsonb_array_elements(coalesce(r->'questionnaireReponses', '[]')) y
                       where y->>'jspId' = moi and y->>'niveau' is not distinct from x->>'niveau' and y->>'rang' is not distinct from x->>'rang'
                         and y->>'date' is not distinct from x->>'date' and y->>'annuel' is not distinct from x->>'annuel') then
      select coalesce(max((y->>'id')::numeric), 0) + 1 into nid from jsonb_array_elements(coalesce(r->'questionnaireReponses', '[]')) y where (y->>'id') ~ '^[0-9.]+$';
      r := jsonb_set(r, '{questionnaireReponses}', coalesce(r->'questionnaireReponses', '[]') || jsonb_build_array(x || jsonb_build_object('id', nid)));
    end if;
  end loop;

  for x in select * from jsonb_array_elements(case when jsonb_typeof(recu->'questionnairesAssignes') = 'array' then recu->'questionnairesAssignes' else '[]' end) loop
    if x->>'jspId' = moi and (x->>'fait') = 'true' then
      i := null;
      select ord - 1 into i from jsonb_array_elements(coalesce(r->'questionnairesAssignes', '[]')) with ordinality t(y, ord)
        where y->>'id' = x->>'id' and y->>'jspId' = moi limit 1;
      if i is not null then r := jsonb_set(r, array['questionnairesAssignes', i::text, 'fait'], 'true'::jsonb); end if;
    end if;
  end loop;

  for m in select * from jsonb_array_elements(case when jsonb_typeof(recu->'messages') = 'array' then recu->'messages' else '[]' end) loop
    for a in select * from jsonb_array_elements(case when jsonb_typeof(m->'accuses') = 'array' then m->'accuses' else '[]' end) loop
      if a->>'jspId' = moi then
        i := null;
        select ord - 1 into i from jsonb_array_elements(coalesce(r->'messages', '[]')) with ordinality t(y, ord)
          where y->>'id' = m->>'id' and y->>'jspId' in ('tous', moi, 'niveau:' || coalesce(promo, '?'))
            and not exists (select 1 from jsonb_array_elements(case when jsonb_typeof(y->'accuses') = 'array' then y->'accuses' else '[]' end) z where z->>'jspId' = moi)
          limit 1;
        if i is not null then
          r := jsonb_set(r, array['messages', i::text, 'accuses'],
                 (case when jsonb_typeof(r->'messages'->i->'accuses') = 'array' then r->'messages'->i->'accuses' else '[]' end)
                 || jsonb_build_array(jsonb_build_object('jspId', a->'jspId', 'ts', a->'ts')));
          r := jsonb_set(r, array['messages', i::text, 'lu'], 'true'::jsonb);
        end if;
      end if;
    end loop;
  end loop;

  for x in select * from jsonb_array_elements(case when jsonb_typeof(recu->'connexionsLog') = 'array' then recu->'connexionsLog' else '[]' end) loop
    if x->>'login' = u->>'login'
       and not exists (select 1 from jsonb_array_elements(coalesce(r->'connexionsLog', '[]')) y where y->>'login' = x->>'login' and y->>'date' = x->>'date') then
      liste := liste || jsonb_build_array(jsonb_build_object('login', u->'login', 'nom', u->'nom', 'role', 'parent', 'date', x->'date'));
    end if;
  end loop;
  if jsonb_array_length(liste) > 0 then
    liste := coalesce(r->'connexionsLog', '[]') || liste;
    select coalesce(jsonb_agg(e order by ord), '[]'::jsonb) into liste
      from jsonb_array_elements(liste) with ordinality t(e, ord) where ord > jsonb_array_length(liste) - 500;
    r := jsonb_set(r, '{connexionsLog}', liste);
  end if;

  return jsonb_set(r, '{users}', coalesce(recu->'users', '[]'));
end $function$;
