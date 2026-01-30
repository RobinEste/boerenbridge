-- Supabase Security Scanner Setup
-- Run this migration to enable the security scanner Edge Function
-- 
-- WARNING: This creates a function that can execute arbitrary SQL
-- Only call this from the Edge Function with service_role key

-- Create schema for security scanner artifacts
CREATE SCHEMA IF NOT EXISTS _security;

-- Table to store scan results
CREATE TABLE IF NOT EXISTS _security.scans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scan_id TEXT NOT NULL UNIQUE,
    project_ref TEXT,
    started_at TIMESTAMPTZ NOT NULL,
    completed_at TIMESTAMPTZ,
    duration_ms INTEGER,
    total_checks INTEGER,
    passed_checks INTEGER,
    failed_checks INTEGER,
    summary JSONB,
    vulnerabilities JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for quick lookups
CREATE INDEX IF NOT EXISTS idx_security_scans_created 
    ON _security.scans (created_at DESC);

-- RLS: Only service role can access
ALTER TABLE _security.scans ENABLE ROW LEVEL SECURITY;

-- No policies = no access from anon/authenticated
-- Only service_role (which bypasses RLS) can read/write


-- Function to execute SQL queries (for the scanner)
-- SECURITY NOTE: This should ONLY be called from Edge Functions with service_role
CREATE OR REPLACE FUNCTION _security.exec_sql(query TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
DECLARE
    result JSONB;
BEGIN
    -- Execute the query and return results as JSON
    EXECUTE format('SELECT COALESCE(jsonb_agg(row_to_json(t)), ''[]''::jsonb) FROM (%s) t', query)
    INTO result;
    
    RETURN result;
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'error', true,
        'message', SQLERRM,
        'detail', SQLSTATE
    );
END;
$$;

-- Revoke public access
REVOKE ALL ON FUNCTION _security.exec_sql(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION _security.exec_sql(TEXT) FROM anon;
REVOKE ALL ON FUNCTION _security.exec_sql(TEXT) FROM authenticated;

-- Only postgres (service_role uses this) can execute
GRANT EXECUTE ON FUNCTION _security.exec_sql(TEXT) TO postgres;


-- Wrapper in public schema for Edge Function RPC calls
-- This checks that the caller has service_role privileges
CREATE OR REPLACE FUNCTION public.exec_sql(query TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
BEGIN
    -- Verify caller has elevated privileges
    -- service_role JWT has role = 'service_role'
    IF current_setting('request.jwt.claims', true)::jsonb->>'role' != 'service_role' THEN
        RAISE EXCEPTION 'Unauthorized: requires service_role';
    END IF;
    
    RETURN _security.exec_sql(query);
END;
$$;

-- Allow authenticated calls (but function checks for service_role)
GRANT EXECUTE ON FUNCTION public.exec_sql(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.exec_sql(TEXT) TO service_role;


-- Optional: Create a view for quick security status
CREATE OR REPLACE VIEW _security.latest_scan AS
SELECT 
    scan_id,
    started_at,
    completed_at,
    duration_ms,
    total_checks,
    passed_checks,
    failed_checks,
    summary,
    jsonb_array_length(vulnerabilities) as vulnerability_count
FROM _security.scans
ORDER BY created_at DESC
LIMIT 1;


-- Helper function to get RLS status for all tables
CREATE OR REPLACE FUNCTION _security.get_rls_status()
RETURNS TABLE (
    schema_name TEXT,
    table_name TEXT,
    rls_enabled BOOLEAN,
    policy_count BIGINT
)
LANGUAGE SQL
SECURITY DEFINER
SET search_path = pg_catalog, public
AS $$
    SELECT 
        n.nspname::TEXT as schema_name,
        c.relname::TEXT as table_name,
        c.relrowsecurity as rls_enabled,
        (SELECT COUNT(*) FROM pg_policies p 
         WHERE p.schemaname = n.nspname AND p.tablename = c.relname) as policy_count
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind = 'r'
      AND n.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast', '_security')
    ORDER BY n.nspname, c.relname;
$$;


-- Log that setup is complete
DO $$
BEGIN
    RAISE NOTICE 'Security scanner setup complete';
    RAISE NOTICE 'Tables created in _security schema';
    RAISE NOTICE 'exec_sql function available for Edge Function calls';
END $$;
