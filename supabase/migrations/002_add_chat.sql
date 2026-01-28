-- =============================================================================
-- MIGRATION: Add chat functionality
-- =============================================================================
-- Run this SQL in Supabase Dashboard > SQL Editor
-- =============================================================================

-- =============================================================================
-- CHAT MESSAGES TABLE
-- =============================================================================

CREATE TABLE IF NOT EXISTS game_chat_messages (
    id BIGSERIAL PRIMARY KEY,
    game_id UUID NOT NULL REFERENCES games(id) ON DELETE CASCADE,
    player_id UUID NOT NULL REFERENCES game_players(id) ON DELETE CASCADE,
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index voor snelle lookups per game
CREATE INDEX idx_chat_messages_game_created
    ON game_chat_messages(game_id, created_at DESC);

-- =============================================================================
-- ROW LEVEL SECURITY
-- =============================================================================

ALTER TABLE game_chat_messages ENABLE ROW LEVEL SECURITY;

-- Spelers kunnen berichten zien in hun eigen game
CREATE POLICY "Players can view chat in their game" ON game_chat_messages
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM game_players
            WHERE game_players.game_id = game_chat_messages.game_id
            AND game_players.user_id = auth.uid()
        )
    );

-- Spelers kunnen berichten sturen in hun eigen game
CREATE POLICY "Players can send chat in their game" ON game_chat_messages
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM game_players
            WHERE game_players.game_id = game_chat_messages.game_id
            AND game_players.user_id = auth.uid()
            AND game_players.id = game_chat_messages.player_id
        )
    );

-- =============================================================================
-- REALTIME
-- =============================================================================

ALTER PUBLICATION supabase_realtime ADD TABLE game_chat_messages;
