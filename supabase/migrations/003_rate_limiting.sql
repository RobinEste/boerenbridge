-- Rate limiting: max 1 game per user per 10 minuten
CREATE OR REPLACE FUNCTION check_game_rate_limit()
RETURNS TRIGGER AS $$
DECLARE
  recent_count INT;
BEGIN
  SELECT COUNT(*) INTO recent_count
  FROM games
  WHERE host_id = NEW.host_id
    AND created_at > NOW() - INTERVAL '10 minutes';

  IF recent_count >= 1 THEN
    RAISE EXCEPTION 'Rate limit: maximaal 1 game per 10 minuten';
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER enforce_game_rate_limit
  BEFORE INSERT ON games
  FOR EACH ROW
  EXECUTE FUNCTION check_game_rate_limit();
