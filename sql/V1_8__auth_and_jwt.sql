-- You can distinguish one user from another in SQL by examining the JWT claims
-- which PostgREST makes available in the SQL variable request.jwt.claim
-- Here's a function to get the email of the currently authenticated user.

-- Prevent current_setting('request.jwt.claim.email') from raising
-- an exception if the setting is not present. Default it to ''.
ALTER DATABASE cashplay SET request.jwt.claim.email TO '';

CREATE OR REPLACE FUNCTION
  cashplay_private.current_email()
  RETURNS TEXT
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN current_setting('request.jwt.claim.email');
END;
$$;

--Singed up user with this function always has an admin (cashplay_admin) role
CREATE OR REPLACE FUNCTION
  cashplay.signup(first_name TEXT, last_name TEXT, company TEXT, email TEXT, pass TEXT)
  RETURNS VOID
AS $$
INSERT INTO cashplay_private.users (first_name, last_name, company, email, pass, role) VALUES
  (signup.first_name, signup.last_name, signup.company, signup.email, signup.pass, 'cashplay_admin');
$$ LANGUAGE SQL;

DROP TYPE IF EXISTS cashplay_private.jwt_token CASCADE;
CREATE TYPE cashplay_private.jwt_token AS (token TEXT);

CREATE OR REPLACE FUNCTION
  cashplay.login(email TEXT, pass TEXT)
  RETURNS cashplay_private.jwt_token
LANGUAGE plpgsql
AS $$
DECLARE
  _role  NAME;
  result cashplay_private.jwt_token;
BEGIN
  -- check email and password
  SELECT cashplay_private.user_role($1, $2)
  INTO _role;
  IF _role IS NULL
  THEN
    RAISE invalid_password
    USING MESSAGE = 'Invalid email or password';
  END IF;

  select cashplay_private.sign(
             row_to_json(r), current_setting('cashplay.jwt_secret')
         ) as token
  from (
         select _role as role, login.email as email,
                extract(epoch from now())::integer + 60*60 as exp
       ) r
  into result;
  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION
cashplay.login(TEXT, TEXT),
cashplay.signup(TEXT, TEXT, TEXT, TEXT, TEXT)
TO cashplay_anonymous;
