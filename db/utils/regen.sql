BEGIN;
\i ./db/utils/drop-schema.sql
\i ./db/utils/create-schema.sql
\i ./db/utils/seed.sql
COMMIT;