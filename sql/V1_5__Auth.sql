--FIXME change secret
ALTER DATABASE cashplay SET "cashplay.jwt_secret" TO 'foo';

CREATE OR REPLACE FUNCTION
  cashplay_private.clearance_for_role(u NAME)
  RETURNS VOID AS
$$
DECLARE
  ok BOOLEAN;
BEGIN
  SELECT exists(
      SELECT rolname
      FROM pg_authid
      WHERE pg_has_role(current_user, oid, 'member')
            AND rolname = u
  )
  INTO ok;
  IF NOT ok
  THEN
    RAISE invalid_password
    USING MESSAGE =
      'current user not member of role ' || u;
  END IF;
END
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION cashplay_private.set_role(role TEXT)
  RETURNS VOID AS $$
BEGIN
  PERFORM cashplay_private.clearance_for_role(role);
  EXECUTE format('SET LOCAL ROLE %I', role);
END $$ LANGUAGE plpgsql;

GRANT EXECUTE on FUNCTION cashplay_private.set_role(text) TO cashplay_authenticator;
