-- Espace de stockage des attestations en PDF (lien envoyé aux familles). Déjà appliqué en production.
-- Lecture par adresse exacte uniquement (aucune politique SELECT : pas de liste possible), nom aléatoire (UUID).
-- Ajout autorisé : PDF, 1 Mo max, nom au format UUID. Pas de modification ni suppression via l'API publique.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('attestations', 'attestations', true, 1048576, array['application/pdf'])
on conflict (id) do update set public = true, file_size_limit = 1048576, allowed_mime_types = array['application/pdf'];
drop policy if exists "attestations ajout" on storage.objects;
create policy "attestations ajout" on storage.objects for insert to public
  with check (bucket_id = 'attestations' and name ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.pdf$');
-- Retour arrière : drop policy "attestations ajout" on storage.objects; delete from storage.buckets where id='attestations';
