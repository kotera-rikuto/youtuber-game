begin;

set local search_path = extensions, public, pg_catalog;

select plan(4);

select ok(
  exists (
    select 1
    from pg_catalog.pg_extension
    where extname = 'btree_gist'
  ),
  'btree_gist extension is installed'
);

select is(
  (
    select namespace.nspname::text
    from pg_catalog.pg_extension as installed_extension
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = installed_extension.extnamespace
    where installed_extension.extname = 'btree_gist'
  ),
  'extensions',
  'btree_gist is installed in the extensions schema'
);

select ok(
  pg_catalog.to_regprocedure('pg_catalog.gen_random_uuid()') is not null,
  'gen_random_uuid is available without pgcrypto'
);

select is(
  (
    select namespace.nspname::text
    from pg_catalog.pg_proc as installed_procedure
    join pg_catalog.pg_namespace as namespace
      on namespace.oid = installed_procedure.pronamespace
    where installed_procedure.oid = pg_catalog.to_regprocedure('pg_catalog.gen_random_uuid()')
  ),
  'pg_catalog',
  'gen_random_uuid is provided by PostgreSQL core'
);

select * from finish();

rollback;
