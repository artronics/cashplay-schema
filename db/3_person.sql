CREATE TABLE IF NOT EXISTS cashplay.person (
  id         SERIAL PRIMARY KEY,
  first_name TEXT NOT NULL CHECK (char_length(first_name) < 80),
  last_name  TEXT CHECK (char_length(last_name) < 80),
  created_at TIMESTAMP DEFAULT now()
);

GRANT UPDATE, DELETE ,INSERT ,SELECT ON cashplay.person TO cashplay_person;

CREATE FUNCTION cashplay.person_full_name(person cashplay.person)
  RETURNS TEXT AS $$
SELECT person.first_name || ' ' || person.last_name
$$ LANGUAGE SQL STABLE;

