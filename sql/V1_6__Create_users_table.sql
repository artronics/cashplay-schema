DROP TABLE IF EXISTS cashplay_private.users CASCADE;
CREATE TABLE
  cashplay_private.users (
  email      TEXT PRIMARY KEY CHECK ( email ~* '^.+@.+\..+$' ),

  first_name TEXT NOT NULL CHECK (length(first_name) < 64),
  last_name  TEXT NOT NULL CHECK (length(first_name) < 64),
  company    TEXT NOT NULL CHECK (length(first_name) < 64),

  pass       TEXT NOT NULL CHECK (length(pass) < 512),
  role       NAME NOT NULL CHECK (length(role) < 512)
);

GRANT SELECT ON TABLE cashplay_private.users TO cashplay_anonymous;
GRANT INSERT ON TABLE cashplay_private.users TO cashplay_anonymous;

-- encrypt pass on insert or update
CREATE OR REPLACE FUNCTION
  cashplay_private.encrypt_pass()
  RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF tg_op = 'INSERT' OR new.pass <> old.pass
  THEN
    new.pass = crypt(new.pass, gen_salt('bf'));
  END IF;
  RETURN new;
END
$$;

CREATE TRIGGER encrypt_pass
BEFORE INSERT OR UPDATE ON cashplay_private.users
FOR EACH ROW
EXECUTE PROCEDURE cashplay_private.encrypt_pass();


-- check if inserted role exists
CREATE OR REPLACE FUNCTION
  cashplay_private.check_role_exists()
  RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NOT exists(SELECT 1
                FROM pg_roles AS r
                WHERE r.rolname = new.role)
  THEN
    RAISE foreign_key_violation
    USING MESSAGE =
      'unknown database role: ' || new.role;
    RETURN NULL;
  END IF;
  RETURN new;
END
$$;


CREATE TRIGGER ensure_user_role_exists
AFTER INSERT OR UPDATE ON cashplay_private.users
FOR EACH ROW
EXECUTE PROCEDURE cashplay_private.check_role_exists();

-- check if username and pass is correct, it returns role
CREATE OR REPLACE FUNCTION
  cashplay_private.user_role(email TEXT, pass TEXT)
  RETURNS NAME
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN (
    SELECT role
    FROM cashplay_private.users AS users
    WHERE users.email = $1
          AND users.pass = crypt($2, users.pass)
  );
END;
$$;
