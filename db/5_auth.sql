CREATE TYPE cashplay.jwt_token AS (
  role      TEXT,
  person_id INTEGER
);


CREATE TABLE IF NOT EXISTS cashplay_private.person_account (
  person_id     INTEGER PRIMARY KEY REFERENCES cashplay.person (id),
  email         TEXT NOT NULL UNIQUE CHECK (email ~* '^.+@.+\..+$'),
  password_hash TEXT NOT NULL
);

CREATE FUNCTION cashplay.register_person(
  first_name TEXT,
  last_name  TEXT,
  email      TEXT,
  password   TEXT
)
  RETURNS cashplay.person AS $$
DECLARE person cashplay.person;
BEGIN

  INSERT INTO cashplay.person (first_name, last_name) VALUES
    (first_name, last_name)
  RETURNING *
    INTO person;

  INSERT INTO cashplay_private.person_account (person_id, email, password_hash) VALUES
    (person.id, email, crypt(password, gen_salt('bf')));
  RETURN person;

END;
$$ LANGUAGE plpgsql STRICT SECURITY DEFINER;

CREATE FUNCTION cashplay.authenticate(
  email    TEXT,
  password TEXT
)
  RETURNS cashplay.jwt_token AS $$
DECLARE
  account cashplay_private.person_account;
BEGIN
  SELECT a.*
  INTO account
  FROM cashplay_private.person_account AS a
  WHERE a.email = $1;

  IF account.password_hash = crypt(password, account.password_hash)
  THEN
    RETURN ('cashplay_person', account.person_id) :: cashplay.jwt_token;
  ELSE
    RETURN NULL;
  END IF;
END;
$$ LANGUAGE plpgsql STRICT SECURITY DEFINER;
grant execute on function cashplay.authenticate(text, text) to cashplay_anonymous, cashplay_person;

CREATE OR REPLACE FUNCTION cashplay.sign_out()
  RETURNS cashplay.jwt_token AS $$
BEGIN
  set local role to 'cashplay_anonymous';
  set local jwt.claims.role to 'cashplay_anonymous';
  RETURN ('cashplay_anonymous', NULL ) :: cashplay.jwt_token;
END;
$$ LANGUAGE plpgsql;

-- The second arg in current_setting is vailabe in
CREATE OR REPLACE FUNCTION cashplay.me()
  RETURNS cashplay.person AS $$
SELECT *
FROM cashplay.person
WHERE id = current_setting('jwt.claims.person_id', TRUE) :: INTEGER
$$ LANGUAGE SQL STABLE;
GRANT EXECUTE ON FUNCTION cashplay.me() TO cashplay_anonymous,cashplay_person;

CREATE OR REPLACE FUNCTION cashplay.is_logged_in()
  RETURNS BOOLEAN AS $$
DECLARE   person    cashplay.person;
  DECLARE person_id INTEGER;
  --  id = current_setting('jwt.claims.person_id',true) :: INTEGER --   DECLARE person RECORD;
BEGIN
  person_id:=current_setting('jwt.claims.person_id', TRUE) :: INTEGER; --   DECLARE person RECORD;
  IF person_id ISNULL
  THEN RETURN FALSE;
  ELSE RETURN TRUE;
  END IF;
END
$$ LANGUAGE plpgsql STABLE;

