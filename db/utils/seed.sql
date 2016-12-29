INSERT INTO cashplay.customer (id, first_name, last_name, created_at) VALUES
  (1, 'Sara', 'Powell', '2015-07-03T14:11:30Z'),
  (2, 'Andrea', 'Fox', '1999-04-04T21:21:42Z'),
  (3, 'Stephen', 'Banks', '2003-12-09T04:39:10Z'),
  (4, 'Kathy','ban', '2001-11-03T15:37:15Z'),
  (5, 'Kenneth', 'Williams', '2002-08-16T19:03:47Z'),
  (6, 'Ann', 'Peterson', '2013-09-24T15:05:29Z');

ALTER SEQUENCE cashplay.customer_id_seq RESTART WITH 7;

GRANT SELECT ON TABLE cashplay.customer to cashplay_anonymous;

SELECT * FROM cashplay.register_person('jalal'::TEXT,'hosseini'::TEXT,'jalalhosseiny@gmail.com'::TEXT,'admin'::TEXT);
