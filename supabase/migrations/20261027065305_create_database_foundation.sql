-- PostgreSQL 17 provides pg_catalog.gen_random_uuid() without an extension.
-- btree_gist supplies GiST operator classes needed by later range exclusion
-- constraints (BE-004 and BE-009). Supabase recommends the extensions schema
-- for extensions that do not require their own dedicated schema.
create extension if not exists btree_gist with schema extensions;

comment on extension btree_gist is
  'GiST operator classes reserved for future range exclusion constraints.';
