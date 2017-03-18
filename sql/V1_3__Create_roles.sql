DROP ROLE IF EXISTS cashplay_login;
CREATE ROLE cashplay_login NOINHERIT LOGIN PASSWORD 'admin';

GRANT cashplay_authenticator TO cashplay_login;

DROP ROLE IF EXISTS cashplay_authenticator;
CREATE ROLE cashplay_authenticator NOINHERIT;

GRANT USAGE ON SCHEMA cashplay_private TO cashplay_authenticator;
GRANT SELECT ON TABLE pg_authid TO cashplay_authenticator;

DROP OWNED BY cashplay_anonymous;
DROP ROLE IF EXISTS cashplay_anonymous;
CREATE ROLE cashplay_anonymous NOLOGIN;

GRANT cashplay_anonymous TO cashplay_authenticator;

GRANT USAGE ON SCHEMA cashplay, cashplay_private TO cashplay_anonymous;
GRANT SELECT ON TABLE pg_authid TO cashplay_anonymous;

DROP OWNED BY cashplay_admin;
DROP ROLE IF EXISTS cashplay_admin;
CREATE ROLE cashplay_admin NOLOGIN;

GRANT cashplay_admin TO cashplay_authenticator;

GRANT USAGE ON SCHEMA cashplay TO cashplay_admin;
