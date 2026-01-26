-- =============================================================================
-- MIGRATION: Fix RLS policies for bot and heartbeat functionality
-- =============================================================================
-- Run this SQL in Supabase Dashboard > SQL Editor
--
-- Problems fixed:
-- 1. game_players: No UPDATE policy (heartbeat/last_seen_at blocked)
-- 2. game_actions: Invalid action_types for bot (bot_bid, bot_play_card)
-- 3. game_actions: No INSERT/SELECT policies
-- 4. game_state: No UPDATE policy
-- =============================================================================

-- 1. Allow players to update their own game_players record (for heartbeat)
CREATE POLICY IF NOT EXISTS "Players can update their own record" ON game_players
    FOR UPDATE USING (user_id = auth.uid());

-- 2. Allow host to update any player in their game
CREATE POLICY IF NOT EXISTS "Host can update players in their game" ON game_players
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM games
            WHERE games.id = game_players.game_id
            AND games.host_id = auth.uid()
        )
    );

-- 3. Fix action_type constraint to include bot actions
ALTER TABLE game_actions DROP CONSTRAINT IF EXISTS game_actions_action_type_check;
ALTER TABLE game_actions ADD CONSTRAINT game_actions_action_type_check
    CHECK (action_type IN (
        'join', 'leave', 'start', 'bid', 'play_card', 'next_round',
        'bot_bid', 'bot_play_card'
    ));

-- 4. Allow players to log actions
CREATE POLICY IF NOT EXISTS "Players can log actions" ON game_actions
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM game_players
            WHERE game_players.game_id = game_actions.game_id
            AND game_players.user_id = auth.uid()
        )
    );

-- 5. Allow players to view actions
CREATE POLICY IF NOT EXISTS "Players can view game actions" ON game_actions
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM game_players
            WHERE game_players.game_id = game_actions.game_id
            AND game_players.user_id = auth.uid()
        )
    );

-- 6. Allow players to update game state
CREATE POLICY IF NOT EXISTS "Players can update game state" ON game_state
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM game_players
            WHERE game_id = game_state.game_id
            AND user_id = auth.uid()
        )
    );
