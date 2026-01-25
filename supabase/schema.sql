-- =============================================================================
-- BOERENBRIDGE SUPABASE SCHEMA
-- =============================================================================
-- Dit schema ondersteunt real-time multiplayer via Supabase Realtime
-- 
-- Architectuur:
-- - games: Spelinstellingen en metadata
-- - game_players: Koppeling spelers aan games
-- - game_state: De actuele spelstaat (wordt real-time gesynchroniseerd)
-- - game_actions: Audit log van alle acties (voor replay/debugging)
-- =============================================================================

-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =============================================================================
-- GAMES TABLE
-- =============================================================================
-- Hoofdtabel voor spelinstanties

CREATE TABLE games (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    
    -- Toegangscode voor vrienden (bijv. "ABCD")
    join_code VARCHAR(6) UNIQUE NOT NULL,
    
    -- Spelregels configuratie (JSON)
    rules JSONB NOT NULL DEFAULT '{
        "scoring_system": 0,
        "round_sequence": 0,
        "screw_the_dealer": true,
        "allow_zero_bid": true,
        "zero_bid_bonus": 0
    }',
    
    -- Game status
    status VARCHAR(20) NOT NULL DEFAULT 'waiting' 
        CHECK (status IN ('waiting', 'playing', 'finished', 'abandoned')),
    
    -- Host (wie heeft het spel aangemaakt)
    host_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    
    -- Timestamps
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    started_at TIMESTAMPTZ,
    finished_at TIMESTAMPTZ,
    
    -- Soft delete
    deleted_at TIMESTAMPTZ
);

-- Index voor join code lookups
CREATE INDEX idx_games_join_code ON games(join_code) WHERE deleted_at IS NULL;

-- =============================================================================
-- GAME PLAYERS TABLE
-- =============================================================================
-- Koppelt spelers aan games, ondersteunt zowel authenticated als guest spelers

CREATE TABLE game_players (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    game_id UUID NOT NULL REFERENCES games(id) ON DELETE CASCADE,
    
    -- Authenticated user (nullable voor guests)
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    
    -- Guest identifier (voor spelers zonder account)
    guest_id VARCHAR(50),
    
    -- Display naam
    display_name VARCHAR(50) NOT NULL,
    
    -- Positie aan tafel (0-indexed)
    seat_position INT NOT NULL,
    
    -- Is deze speler nog verbonden?
    is_connected BOOLEAN NOT NULL DEFAULT true,
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    
    -- Timestamps
    joined_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    left_at TIMESTAMPTZ,
    
    -- Constraints
    CONSTRAINT unique_seat_per_game UNIQUE (game_id, seat_position),
    CONSTRAINT player_identifier CHECK (user_id IS NOT NULL OR guest_id IS NOT NULL)
);

-- Index voor game lookups
CREATE INDEX idx_game_players_game_id ON game_players(game_id);

-- =============================================================================
-- GAME STATE TABLE
-- =============================================================================
-- De actuele spelstaat - dit is wat real-time gesynchroniseerd wordt

CREATE TABLE game_state (
    game_id UUID PRIMARY KEY REFERENCES games(id) ON DELETE CASCADE,
    
    -- Volledige spelstaat als JSON
    -- Dit bevat: fase, huidige ronde, biedingen, kaarten in slag, etc.
    state JSONB NOT NULL DEFAULT '{}',
    
    -- Versie voor optimistic locking
    version INT NOT NULL DEFAULT 0,
    
    -- Laatste update
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =============================================================================
-- GAME ACTIONS TABLE
-- =============================================================================
-- Audit log van alle spelacties (voor replay, debugging, anti-cheat)

CREATE TABLE game_actions (
    id BIGSERIAL PRIMARY KEY,
    game_id UUID NOT NULL REFERENCES games(id) ON DELETE CASCADE,
    
    -- Wie deed de actie
    player_id UUID NOT NULL REFERENCES game_players(id) ON DELETE CASCADE,
    
    -- Type actie
    action_type VARCHAR(30) NOT NULL 
        CHECK (action_type IN ('join', 'leave', 'start', 'bid', 'play_card', 'next_round')),
    
    -- Actie details (bijv. welke kaart gespeeld)
    payload JSONB,
    
    -- State version before this action
    state_version INT NOT NULL,
    
    -- Timestamp
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index voor game action lookups
CREATE INDEX idx_game_actions_game_id ON game_actions(game_id);

-- =============================================================================
-- ROW LEVEL SECURITY
-- =============================================================================

ALTER TABLE games ENABLE ROW LEVEL SECURITY;
ALTER TABLE game_players ENABLE ROW LEVEL SECURITY;
ALTER TABLE game_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE game_actions ENABLE ROW LEVEL SECURITY;

-- Games: iedereen kan lezen (nodig voor join), alleen host kan updaten
CREATE POLICY "Games are viewable by everyone" ON games
    FOR SELECT USING (true);

CREATE POLICY "Games can be created by anyone" ON games
    FOR INSERT WITH CHECK (true);

CREATE POLICY "Games can be updated by host" ON games
    FOR UPDATE USING (auth.uid() = host_id);

-- Game players: spelers in het spel kunnen lezen
CREATE POLICY "Players in game can view all players" ON game_players
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM game_players gp 
            WHERE gp.game_id = game_players.game_id 
            AND (gp.user_id = auth.uid() OR gp.guest_id IS NOT NULL)
        )
    );

CREATE POLICY "Anyone can join a game" ON game_players
    FOR INSERT WITH CHECK (true);

-- Game state: alleen spelers in het spel
CREATE POLICY "Players can view game state" ON game_state
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM game_players 
            WHERE game_id = game_state.game_id 
            AND (user_id = auth.uid() OR guest_id IS NOT NULL)
        )
    );

-- =============================================================================
-- REALTIME SUBSCRIPTIONS
-- =============================================================================
-- Enable realtime voor de tabellen die we willen syncen

ALTER PUBLICATION supabase_realtime ADD TABLE game_state;
ALTER PUBLICATION supabase_realtime ADD TABLE game_players;

-- =============================================================================
-- FUNCTIONS
-- =============================================================================

-- Genereer een unieke join code
CREATE OR REPLACE FUNCTION generate_join_code()
RETURNS VARCHAR(6) AS $$
DECLARE
    chars VARCHAR(26) := 'ABCDEFGHJKLMNPQRSTUVWXYZ';  -- Geen I, O (lijken op 1, 0)
    result VARCHAR(6) := '';
    i INT;
BEGIN
    FOR i IN 1..4 LOOP
        result := result || SUBSTR(chars, FLOOR(RANDOM() * LENGTH(chars) + 1)::INT, 1);
    END LOOP;
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Trigger om join code te genereren bij insert
CREATE OR REPLACE FUNCTION set_join_code()
RETURNS TRIGGER AS $$
DECLARE
    new_code VARCHAR(6);
    code_exists BOOLEAN;
BEGIN
    IF NEW.join_code IS NULL THEN
        LOOP
            new_code := generate_join_code();
            SELECT EXISTS(SELECT 1 FROM games WHERE join_code = new_code) INTO code_exists;
            EXIT WHEN NOT code_exists;
        END LOOP;
        NEW.join_code := new_code;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER games_set_join_code
    BEFORE INSERT ON games
    FOR EACH ROW
    EXECUTE FUNCTION set_join_code();

-- Trigger om game_state aan te maken wanneer een game wordt aangemaakt
CREATE OR REPLACE FUNCTION create_game_state()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO game_state (game_id, state)
    VALUES (NEW.id, '{"phase": 0, "players": []}');
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER games_create_state
    AFTER INSERT ON games
    FOR EACH ROW
    EXECUTE FUNCTION create_game_state();

-- =============================================================================
-- HELPER VIEWS
-- =============================================================================

-- Overzicht van actieve games met speleraantallen
CREATE OR REPLACE VIEW active_games AS
SELECT 
    g.id,
    g.join_code,
    g.status,
    g.rules,
    g.created_at,
    COUNT(gp.id) AS player_count,
    ARRAY_AGG(gp.display_name ORDER BY gp.seat_position) AS player_names
FROM games g
LEFT JOIN game_players gp ON g.id = gp.game_id AND gp.left_at IS NULL
WHERE g.deleted_at IS NULL
  AND g.status IN ('waiting', 'playing')
GROUP BY g.id;
