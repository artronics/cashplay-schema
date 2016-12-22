BEGIN;
\i ./db/1_schema.sql
\i ./db/2_company.sql
\i ./db/3_person.sql
\i ./db/4_customer.sql
\i ./db/5_auth.sql
COMMIT;