-- pg_cron Setup for Automated Security Scanning
-- 
-- This sets up automated daily security scans using pg_cron.
-- Requires pg_cron extension to be enabled in your Supabase project.
--
-- Enable in Supabase Dashboard: Database > Extensions > pg_cron

-- Enable the extension (if not already enabled)
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Grant usage to postgres role
GRANT USAGE ON SCHEMA cron TO postgres;

-- ============================================
-- OPTION 1: Direct HTTP call to Edge Function
-- ============================================

-- Schedule daily scan at 6 AM UTC
SELECT cron.schedule(
    'daily-security-scan',          -- job name
    '0 6 * * *',                    -- cron expression: 6 AM UTC daily
    $$
    SELECT net.http_post(
        url := current_setting('app.settings.supabase_url') || '/functions/v1/security-scanner',
        headers := jsonb_build_object(
            'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key'),
            'Content-Type', 'application/json'
        ),
        body := '{"config": {"severity_threshold": "low", "notifications": {"github_issues": true}}}'::jsonb
    );
    $$
);

-- ============================================
-- OPTION 2: Using pg_net extension (recommended)
-- ============================================

-- Enable pg_net if not already
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Create a function to trigger the scan
CREATE OR REPLACE FUNCTION _security.trigger_scan()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    supabase_url TEXT;
    service_key TEXT;
BEGIN
    -- Get configuration from vault or settings
    -- Option A: From app settings
    supabase_url := current_setting('app.settings.supabase_url', true);
    service_key := current_setting('app.settings.service_role_key', true);
    
    -- Option B: From Supabase Vault (more secure)
    -- SELECT decrypted_secret INTO service_key 
    -- FROM vault.decrypted_secrets 
    -- WHERE name = 'service_role_key';
    
    IF supabase_url IS NULL OR service_key IS NULL THEN
        RAISE EXCEPTION 'Configuration not set. Please configure app.settings.supabase_url and app.settings.service_role_key';
    END IF;
    
    -- Make HTTP request to Edge Function
    PERFORM net.http_post(
        url := supabase_url || '/functions/v1/security-scanner',
        headers := jsonb_build_object(
            'Authorization', 'Bearer ' || service_key,
            'Content-Type', 'application/json'
        ),
        body := jsonb_build_object(
            'config', jsonb_build_object(
                'severity_threshold', 'low',
                'notifications', jsonb_build_object(
                    'github_issues', true
                )
            )
        )
    );
    
    RAISE NOTICE 'Security scan triggered at %', NOW();
END;
$$;

-- Schedule using the function
SELECT cron.schedule(
    'daily-security-scan-v2',
    '0 6 * * *',
    'SELECT _security.trigger_scan()'
);


-- ============================================
-- MANAGE SCHEDULED JOBS
-- ============================================

-- View all scheduled jobs
-- SELECT * FROM cron.job;

-- View job run history
-- SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;

-- Unschedule a job
-- SELECT cron.unschedule('daily-security-scan');

-- Run job manually (for testing)
-- SELECT _security.trigger_scan();


-- ============================================
-- CONFIGURATION SETUP
-- ============================================

-- Set app configuration (run once, or add to your config)
-- These should be set securely, not in plain SQL in production!

-- Option 1: Using ALTER DATABASE (persists)
-- ALTER DATABASE postgres SET app.settings.supabase_url = 'https://your-project.supabase.co';
-- ALTER DATABASE postgres SET app.settings.service_role_key = 'your-key';

-- Option 2: Using Supabase Vault (more secure, recommended)
/*
-- Store secrets in vault
SELECT vault.create_secret(
    'service_role_key',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
    'Service role key for security scanner'
);

-- Then modify trigger_scan() to read from vault:
SELECT decrypted_secret INTO service_key 
FROM vault.decrypted_secrets 
WHERE name = 'service_role_key';
*/


-- ============================================
-- ALTERNATIVE: Webhook-based trigger
-- ============================================

-- If you prefer to trigger scans from external sources,
-- you can create a webhook endpoint that calls the scan

CREATE OR REPLACE FUNCTION _security.webhook_trigger_scan()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Trigger scan when a new record is inserted
    -- into a monitoring table
    PERFORM _security.trigger_scan();
    RETURN NEW;
END;
$$;

-- Example: Trigger scan when deployment happens
-- CREATE TRIGGER on_deployment_scan
-- AFTER INSERT ON deployments
-- FOR EACH ROW
-- EXECUTE FUNCTION _security.webhook_trigger_scan();
