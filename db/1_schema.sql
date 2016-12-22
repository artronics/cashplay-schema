CREATE SCHEMA cashplay;
CREATE SCHEMA cashplay_private;

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE ROLE cashplay_postgraphql LOGIN SUPERUSER PASSWORD 'admin';


CREATE ROLE cashplay_person;
GRANT cashplay_person TO cashplay_postgraphql;
CREATE ROLE cashplay_anonymous;
GRANT cashplay_anonymous TO cashplay_postgraphql;

GRANT USAGE ON SCHEMA cashplay TO cashplay_person,cashplay_anonymous;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA cashplay TO cashplay_person,cashplay_anonymous;


