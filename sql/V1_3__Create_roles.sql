DO
$body$
BEGIN
  IF NOT EXISTS (
      SELECT *
      FROM   pg_roles
      WHERE  rolname = 'cashplay_login') THEN

    CREATE ROLE cashplay_login LOGIN PASSWORD 'admin';
  END IF;
END
$body$;


DO
$body$
BEGIN
  IF NOT EXISTS (
      SELECT *
      FROM   pg_roles
      WHERE  rolname = 'cashplay_authenticator') THEN

    CREATE ROLE cashplay_authenticator NOINHERIT ;
  END IF;
END
$body$;

GRANT cashplay_authenticator TO cashplay_login;

GRANT USAGE ON SCHEMA cashplay_private TO cashplay_authenticator;
GRANT SELECT ON TABLE pg_authid TO cashplay_authenticator;

DO
$body$
BEGIN
  IF NOT EXISTS (
      SELECT *
      FROM   pg_roles
      WHERE  rolname = 'cashplay_anonymous') THEN

    CREATE ROLE cashplay_anonymous NOLOGIN ;
  END IF;
END
$body$;

GRANT cashplay_anonymous TO cashplay_authenticator;

GRANT USAGE ON SCHEMA cashplay, cashplay_private TO cashplay_anonymous;
GRANT SELECT ON TABLE pg_authid TO cashplay_anonymous;

DO
$body$
BEGIN
  IF NOT EXISTS (
      SELECT *
      FROM   pg_roles
      WHERE  rolname = 'cashplay_admin') THEN

    CREATE ROLE cashplay_admin NOLOGIN ;
  END IF;
END
$body$;

GRANT cashplay_admin TO cashplay_authenticator;

GRANT USAGE ON SCHEMA cashplay TO cashplay_admin;
