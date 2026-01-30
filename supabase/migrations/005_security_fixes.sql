-- =============================================================================
-- MIGRATION: Security fixes from automated scan
-- =============================================================================
-- Fixes:
-- 1. Permissive RLS policies op games en game_players beperken tot authenticated
-- 2. cleanup_old_games() search_path vastleggen
-- 3. Ontbrekende indexes op foreign key kolommen
--
-- Realtime op game-tabellen is by design (multiplayer spel) en wordt niet gewijzigd.
-- =============================================================================


-- =============================================================================
-- 1. RLS: Beperk SELECT policies tot authenticated users
-- =============================================================================

-- Verwijder de te brede policies
DROP POLICY IF EXISTS "Games are viewable by everyone" ON games;
DROP POLICY IF EXISTS "Game players are viewable" ON game_players;

-- Vervang door authenticated-only policies
CREATE POLICY "Games are viewable by authenticated users" ON games
    FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "Game players are viewable by authenticated users" ON game_players
    FOR SELECT
    TO authenticated
    USING (true);


-- =============================================================================
-- 2. Fix search_path op cleanup_old_games()
-- =============================================================================

CREATE OR REPLACE FUNCTION public.cleanup_old_games()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
    deleted_games integer;
    deleted_players integer;
    deleted_states integer;
BEGIN
    -- Verwijder game_state van oude games
    DELETE FROM game_state
    WHERE game_id IN (
        SELECT id FROM games
        WHERE status IN ('waiting', 'playing')
            AND created_at < NOW() - INTERVAL '24 hours'
    );
    GET DIAGNOSTICS deleted_states = ROW_COUNT;

    -- Verwijder game_players van oude games
    DELETE FROM game_players
    WHERE game_id IN (
        SELECT id FROM games
        WHERE status IN ('waiting', 'playing')
            AND created_at < NOW() - INTERVAL '24 hours'
    );
    GET DIAGNOSTICS deleted_players = ROW_COUNT;

    -- Verwijder de games zelf
    DELETE FROM games
    WHERE status IN ('waiting', 'playing')
        AND created_at < NOW() - INTERVAL '24 hours';
    GET DIAGNOSTICS deleted_games = ROW_COUNT;

    RETURN jsonb_build_object(
        'deleted_games', deleted_games,
        'deleted_players', deleted_players,
        'deleted_states', deleted_states
    );
END;
$function$;


-- =============================================================================
-- 3. Indexes op foreign key kolommen
-- =============================================================================

CREATE INDEX IF NOT EXISTS idx_game_players_user_id
    ON public.game_players (user_id);

CREATE INDEX IF NOT EXISTS idx_games_host_id
    ON public.games (host_id);

CREATE INDEX IF NOT EXISTS idx_game_actions_player_id
    ON public.game_actions (player_id);

CREATE INDEX IF NOT EXISTS idx_game_chat_messages_player_id
    ON public.game_chat_messages (player_id);
