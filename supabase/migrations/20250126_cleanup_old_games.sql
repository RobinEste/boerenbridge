-- =============================================================================
-- Automatische cleanup van oude games
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Cleanup functie
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION cleanup_old_games()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  deleted_games integer;
  deleted_players integer;
  deleted_states integer;
  deleted_actions integer;
BEGIN
  -- Verwijder game_actions van oude games
  WITH old_games AS (
    SELECT id FROM games
    WHERE status IN ('waiting', 'playing')
      AND created_at < NOW() - INTERVAL '24 hours'
  )
  DELETE FROM game_actions
  WHERE game_id IN (SELECT id FROM old_games);
  GET DIAGNOSTICS deleted_actions = ROW_COUNT;

  -- Verwijder game_state van oude games
  WITH old_games AS (
    SELECT id FROM games
    WHERE status IN ('waiting', 'playing')
      AND created_at < NOW() - INTERVAL '24 hours'
  )
  DELETE FROM game_state
  WHERE game_id IN (SELECT id FROM old_games);
  GET DIAGNOSTICS deleted_states = ROW_COUNT;

  -- Verwijder game_players van oude games
  WITH old_games AS (
    SELECT id FROM games
    WHERE status IN ('waiting', 'playing')
      AND created_at < NOW() - INTERVAL '24 hours'
  )
  DELETE FROM game_players
  WHERE game_id IN (SELECT id FROM old_games);
  GET DIAGNOSTICS deleted_players = ROW_COUNT;

  -- Verwijder de games zelf
  DELETE FROM games
  WHERE status IN ('waiting', 'playing')
    AND created_at < NOW() - INTERVAL '24 hours';
  GET DIAGNOSTICS deleted_games = ROW_COUNT;

  -- Return statistieken
  RETURN jsonb_build_object(
    'deleted_games', deleted_games,
    'deleted_players', deleted_players,
    'deleted_states', deleted_states,
    'deleted_actions', deleted_actions,
    'cleanup_time', NOW()
  );
END;
$$;

-- -----------------------------------------------------------------------------
-- 2. Functie om cleanup handmatig of via API aan te roepen
-- -----------------------------------------------------------------------------
-- Deze kan worden aangeroepen via: SELECT cleanup_old_games();
-- Of via Supabase RPC: supabase.rpc('cleanup_old_games')

-- -----------------------------------------------------------------------------
-- 3. Optioneel: pg_cron scheduling (alleen Pro plan)
-- -----------------------------------------------------------------------------
-- Uncomment deze regels als je Supabase Pro hebt:
--
-- CREATE EXTENSION IF NOT EXISTS pg_cron;
-- SELECT cron.schedule(
--   'cleanup-old-games',           -- job naam
--   '0 3 * * *',                   -- elke dag om 03:00 UTC
--   'SELECT cleanup_old_games()'   -- uit te voeren query
-- );

-- -----------------------------------------------------------------------------
-- 4. Helper view om oude games te bekijken
-- -----------------------------------------------------------------------------
CREATE OR REPLACE VIEW old_games_overview AS
SELECT
  g.id,
  g.join_code,
  g.status,
  g.created_at,
  NOW() - g.created_at as age,
  COUNT(gp.id) as player_count,
  CASE
    WHEN g.created_at < NOW() - INTERVAL '24 hours' THEN 'will be deleted'
    ELSE 'active'
  END as cleanup_status
FROM games g
LEFT JOIN game_players gp ON gp.game_id = g.id
WHERE g.status IN ('waiting', 'playing')
GROUP BY g.id
ORDER BY g.created_at DESC;

-- -----------------------------------------------------------------------------
-- 5. Grant permissions
-- -----------------------------------------------------------------------------
-- Functie mag door service_role worden aangeroepen (voor GitHub Actions)
-- en door authenticated users (voor admin functionaliteit)
GRANT EXECUTE ON FUNCTION cleanup_old_games() TO service_role;

-- View is leesbaar voor iedereen (handig voor debugging)
GRANT SELECT ON old_games_overview TO anon;
GRANT SELECT ON old_games_overview TO authenticated;
