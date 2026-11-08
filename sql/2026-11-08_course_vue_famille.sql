-- Course 2 000 m : les comptes famille reçoivent uniquement les temps de leur enfant.
-- DB.course = { objectif, seances: { "AAAA-MM-JJ": { distance, temps: { "<jspId>": "mm:ss" }, obs } } }
-- Vue famille : { objectif, seances: { date: { distance, temps: { moi: t } } } } (pas d'observations,
-- pas les temps des autres JSP). Les écritures des familles sur « course » restent ignorées
-- (carnet_fusion_famille ne reprend pas cette clé).
CREATE OR REPLACE FUNCTION public.carnet_vue_famille(d jsonb, u jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
declare
  moi text := u->>'jspId';
  promo text;
  res jsonb := '{}'::jsonb;
  k text; v jsonb;
  communs text[] := array['saison', 'allSaisons', 'planning', 'reglement', 'organigramme',
                          'questionsCulture', 'questionsCultureVersion', 'settingsCandidature',
                          'equipesPedagogiques'];
  internes text[] := array['connexionsLog', 'finance', 'icp', 'stockHabillement',
                           'commandesHabillement', 'mouvementsHabillement', 'competitions'];
begin
  if d is null then return d; end if;
  select x->>'promotion' into promo from jsonb_array_elements(coalesce(d->'jsps', '[]')) x where x->>'id' = moi limit 1;
  for k, v in select * from jsonb_each(d) loop
    if k = any(communs) then
      res := res || jsonb_build_object(k, v);
    elsif k = 'users' then
      res := res || jsonb_build_object('users', coalesce((select jsonb_agg(x - 'pass') from jsonb_array_elements(v) x where x->>'login' = u->>'login'), '[]'::jsonb));
    elsif k = 'jsps' then
      res := res || jsonb_build_object('jsps', coalesce((select jsonb_agg(x) from jsonb_array_elements(v) x where x->>'id' = moi), '[]'::jsonb));
    elsif k = 'messages' and jsonb_typeof(v) = 'array' then
      res := res || jsonb_build_object('messages', coalesce((
        select jsonb_agg(x || jsonb_build_object('accuses', coalesce((select jsonb_agg(a) from jsonb_array_elements(case when jsonb_typeof(x->'accuses') = 'array' then x->'accuses' else '[]' end) a where a->>'jspId' = moi), '[]'::jsonb)))
        from jsonb_array_elements(v) x
        where x->>'jspId' in ('tous', moi, 'niveau:' || coalesce(promo, '?'))), '[]'::jsonb));
    elsif k = 'documents' and jsonb_typeof(v) = 'object' then
      res := res || jsonb_build_object('documents', coalesce((select jsonb_object_agg(s, jsonb_build_object(moi, sv->moi)) from jsonb_each(v) t(s, sv) where jsonb_typeof(sv) = 'object' and sv ? moi), '{}'::jsonb));
    elsif k = 'course' and jsonb_typeof(v) = 'object' then
      res := res || jsonb_build_object('course', jsonb_build_object(
        'objectif', v->'objectif',
        'seances', coalesce((select jsonb_object_agg(s, jsonb_build_object('distance', sv->'distance', 'temps', jsonb_build_object(moi, sv->'temps'->moi)))
                             from jsonb_each(case when jsonb_typeof(v->'seances') = 'object' then v->'seances' else '{}' end) t(s, sv)
                             where jsonb_typeof(sv) = 'object' and jsonb_typeof(sv->'temps') = 'object' and sv->'temps' ? moi), '{}'::jsonb)));
    elsif jsonb_typeof(v) = 'array' and not (k = any(internes)) then
      res := res || jsonb_build_object(k, coalesce((select jsonb_agg(x) from jsonb_array_elements(v) x where jsonb_typeof(x) = 'object' and x->>'jspId' = moi), '[]'::jsonb));
    end if;
  end loop;
  return res;
end $function$;
