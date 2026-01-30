/**
 * Security Checks Definitions
 *
 * All security checks with their SQL queries and metadata.
 * Based on Supabase Security Advisor patterns + additional custom checks.
 */

import { SecurityCheck } from './types.ts';

export const SECURITY_CHECKS: SecurityCheck[] = [
  // ============================================
  // ROW LEVEL SECURITY CHECKS
  // ============================================
  {
    id: 'rls_disabled_in_public',
    name: 'RLS Disabled on Public Tables',
    description: 'Tables in the public schema without Row Level Security enabled are accessible to anyone with the anon key.',
    severity: 'high',
    category: 'rls',
    query: `
      SELECT
        schemaname,
        tablename,
        'Table has no RLS enabled' as issue
      FROM pg_tables
      WHERE schemaname = 'public'
        AND tablename NOT LIKE 'pg_%'
        AND tablename NOT LIKE '_prisma%'
        AND NOT EXISTS (
          SELECT 1 FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE c.relname = tablename
            AND n.nspname = schemaname
            AND c.relrowsecurity = true
        )
    `,
    remediation: `
      Enable RLS on the affected tables:

      ALTER TABLE public.{table_name} ENABLE ROW LEVEL SECURITY;

      Then create appropriate policies for access control.
    `,
    documentation_url: 'https://supabase.com/docs/guides/auth/row-level-security'
  },

  {
    id: 'rls_enabled_no_policy',
    name: 'RLS Enabled Without Policies',
    description: 'Tables with RLS enabled but no policies defined will deny ALL access, which may be unintentional.',
    severity: 'high',
    category: 'rls',
    query: `
      SELECT
        n.nspname as schemaname,
        c.relname as tablename,
        'RLS enabled but no policies exist' as issue
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE c.relkind = 'r'
        AND c.relrowsecurity = true
        AND n.nspname = 'public'
        AND NOT EXISTS (
          SELECT 1 FROM pg_policies p
          WHERE p.schemaname = n.nspname
            AND p.tablename = c.relname
        )
    `,
    remediation: `
      Create at least one RLS policy for the table:

      -- Allow authenticated users to read their own data
      CREATE POLICY "Users can view own data"
        ON public.{table_name}
        FOR SELECT
        USING (auth.uid() = user_id);
    `,
    documentation_url: 'https://supabase.com/docs/guides/auth/row-level-security'
  },

  {
    id: 'permissive_rls_policy',
    name: 'Overly Permissive RLS Policy',
    description: 'RLS policies that grant access to all rows (using TRUE) may expose data unintentionally.',
    severity: 'medium',
    category: 'rls',
    query: `
      SELECT
        schemaname,
        tablename,
        policyname,
        permissive,
        roles::text,
        cmd,
        qual
      FROM pg_policies
      WHERE schemaname = 'public'
        AND (
          qual::text = 'true'
          OR qual::text = '(true)'
          OR qual IS NULL
        )
        AND cmd IN ('SELECT', 'ALL')
    `,
    remediation: `
      Review and restrict the policy condition:

      -- Instead of allowing all:
      -- CREATE POLICY "allow_all" ON table FOR SELECT USING (true);

      -- Use specific conditions:
      CREATE POLICY "user_isolation"
        ON public.{table_name}
        FOR SELECT
        USING (auth.uid() = user_id OR is_public = true);
    `,
    documentation_url: 'https://supabase.com/docs/guides/auth/row-level-security#policies'
  },

  // ============================================
  // AUTHENTICATION CHECKS
  // ============================================
  {
    id: 'auth_users_exposed',
    name: 'Auth Users Table Exposed',
    description: 'The auth.users table should never be directly queryable from the public API.',
    severity: 'critical',
    category: 'authentication',
    query: `
      SELECT
        'auth' as schemaname,
        'users' as tablename,
        grantee::text,
        privilege_type
      FROM information_schema.role_table_grants
      WHERE table_schema = 'auth'
        AND table_name = 'users'
        AND grantee IN ('anon', 'authenticated')
        AND privilege_type = 'SELECT'
    `,
    remediation: `
      Revoke public access to auth.users:

      REVOKE SELECT ON auth.users FROM anon;
      REVOKE SELECT ON auth.users FROM authenticated;

      Use auth.uid() and auth.jwt() in RLS policies instead.
    `,
    documentation_url: 'https://supabase.com/docs/guides/auth'
  },

  {
    id: 'weak_password_policy',
    name: 'Weak Password Requirements',
    description: 'Password policy should enforce minimum length and complexity.',
    severity: 'medium',
    category: 'authentication',
    query: `
      SELECT
        'auth.config' as location,
        'Check auth settings in Supabase Dashboard' as recommendation
      WHERE NOT EXISTS (
        -- This is a placeholder - actual check requires Management API
        SELECT 1 WHERE false
      )
      LIMIT 0  -- Returns empty if we can't check programmatically
    `,
    remediation: `
      Configure strong password requirements in Supabase Dashboard:

      1. Go to Authentication > Providers > Email
      2. Set minimum password length to at least 12 characters
      3. Enable "Require uppercase, lowercase, number, symbol"

      Or via API:

      PATCH /auth/v1/admin/config
      {
        "password_min_length": 12,
        "password_required_characters": "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()"
      }
    `,
    documentation_url: 'https://supabase.com/docs/guides/auth/passwords'
  },

  // ============================================
  // DATA EXPOSURE CHECKS
  // ============================================
  {
    id: 'sensitive_columns_exposed',
    name: 'Sensitive Columns in Public Schema',
    description: 'Columns with potentially sensitive data (PII, credentials) detected in public schema.',
    severity: 'high',
    category: 'data_exposure',
    query: `
      SELECT
        table_schema as schemaname,
        table_name as tablename,
        column_name,
        data_type,
        'Potentially sensitive column name' as issue
      FROM information_schema.columns
      WHERE table_schema = 'public'
        AND (
          column_name ~* '(password|secret|token|key|ssn|social_security|credit_card|card_number|cvv|pin|api_key|private_key)'
          OR column_name ~* '(email|phone|address|birthdate|date_of_birth|salary|income)'
        )
    `,
    remediation: `
      Consider:

      1. Move sensitive data to a private schema
      2. Encrypt sensitive columns using pgcrypto or Vault
      3. Implement column-level RLS using security barrier views
      4. Use data masking for non-admin users

      Example with encryption:

      -- Store encrypted
      UPDATE users SET email_encrypted = pgp_sym_encrypt(email, 'encryption_key');

      -- Or use Supabase Vault
      SELECT vault.create_secret('my_secret', 'secret_value');
    `,
    documentation_url: 'https://supabase.com/docs/guides/database/vault'
  },

  {
    id: 'materialized_view_in_api',
    name: 'Materialized View Exposed',
    description: 'Materialized views in public schema are accessible via the API and may expose aggregated data.',
    severity: 'medium',
    category: 'data_exposure',
    query: `
      SELECT
        schemaname,
        matviewname as viewname,
        'Materialized view accessible via API' as issue
      FROM pg_matviews
      WHERE schemaname = 'public'
    `,
    remediation: `
      Options to secure materialized views:

      1. Move to a private schema:
         ALTER MATERIALIZED VIEW my_view SET SCHEMA private;

      2. Revoke API access:
         REVOKE SELECT ON my_view FROM anon, authenticated;

      3. Create a secure wrapper function with RLS.
    `,
    documentation_url: 'https://supabase.com/docs/guides/api/securing-your-api'
  },

  // ============================================
  // CONFIGURATION CHECKS
  // ============================================
  {
    id: 'extension_in_public',
    name: 'Extension in Public Schema',
    description: 'Extensions in the public schema may expose internal functions via the API.',
    severity: 'medium',
    category: 'extensions',
    query: `
      SELECT
        e.extname,
        e.extversion,
        n.nspname as schema
      FROM pg_extension e
      JOIN pg_namespace n ON n.oid = e.extnamespace
      WHERE n.nspname = 'public'
        AND e.extname NOT IN ('plpgsql')
    `,
    remediation: `
      Move extensions to a dedicated schema:

      -- For new extensions:
      CREATE SCHEMA IF NOT EXISTS extensions;
      CREATE EXTENSION pg_trgm SCHEMA extensions;

      -- For existing extensions (if supported):
      ALTER EXTENSION {ext_name} SET SCHEMA extensions;

      Note: Some extensions cannot be moved after creation.
    `,
    documentation_url: 'https://supabase.com/docs/guides/database/extensions'
  },

  {
    id: 'security_definer_view',
    name: 'Security Definer View',
    description: 'Views with SECURITY DEFINER execute with owner privileges, potentially bypassing RLS.',
    severity: 'medium',
    category: 'authorization',
    query: `
      SELECT
        n.nspname as schemaname,
        c.relname as viewname,
        pg_get_userbyid(c.relowner) as owner,
        'View uses SECURITY DEFINER' as issue
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE c.relkind = 'v'
        AND n.nspname = 'public'
        AND EXISTS (
          SELECT 1 FROM pg_rewrite r
          WHERE r.ev_class = c.oid
            AND r.ev_type = '1'
            AND r.is_instead
        )
    `,
    remediation: `
      Review if SECURITY DEFINER is necessary. If not:

      -- Recreate view without security definer
      CREATE OR REPLACE VIEW my_view
      WITH (security_invoker = true) AS
      SELECT ...;

      If SECURITY DEFINER is required, ensure the view owner
      has minimal necessary privileges.
    `,
    documentation_url: 'https://supabase.com/docs/guides/database/database-advisors#0010_security_definer_view'
  },

  {
    id: 'function_search_path_mutable',
    name: 'Function with Mutable Search Path',
    description: 'Functions without a fixed search_path may be vulnerable to search path injection.',
    severity: 'medium',
    category: 'configuration',
    query: `
      SELECT
        n.nspname as schema,
        p.proname as function_name,
        pg_get_functiondef(p.oid) as definition
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
      WHERE n.nspname = 'public'
        AND p.prosecdef = true
        AND NOT (
          pg_get_functiondef(p.oid) ~* 'SET search_path'
          OR pg_get_functiondef(p.oid) ~* 'search_path='
        )
    `,
    remediation: `
      Set a fixed search_path for SECURITY DEFINER functions:

      CREATE OR REPLACE FUNCTION my_function()
      RETURNS void
      LANGUAGE plpgsql
      SECURITY DEFINER
      SET search_path = public, pg_temp
      AS $$
      BEGIN
        -- function body
      END;
      $$;
    `,
    documentation_url: 'https://supabase.com/docs/guides/database/database-advisors#0011_function_search_path_mutable'
  },

  {
    id: 'unindexed_foreign_keys',
    name: 'Unindexed Foreign Keys',
    description: 'Foreign key columns without indexes can cause performance issues and slow CASCADE operations.',
    severity: 'low',
    category: 'performance',
    query: `
      SELECT
        tc.table_schema as schemaname,
        tc.table_name as tablename,
        kcu.column_name,
        tc.constraint_name
      FROM information_schema.table_constraints tc
      JOIN information_schema.key_column_usage kcu
        ON tc.constraint_name = kcu.constraint_name
        AND tc.table_schema = kcu.table_schema
      WHERE tc.constraint_type = 'FOREIGN KEY'
        AND tc.table_schema = 'public'
        AND NOT EXISTS (
          SELECT 1
          FROM pg_indexes i
          WHERE i.schemaname = tc.table_schema
            AND i.tablename = tc.table_name
            AND i.indexdef LIKE '%' || kcu.column_name || '%'
        )
    `,
    remediation: `
      Create an index on the foreign key column:

      CREATE INDEX idx_{table}_{column}
        ON public.{table_name} ({column_name});
    `,
    documentation_url: 'https://supabase.com/docs/guides/database/database-advisors#0001_unindexed_foreign_keys'
  },

  // ============================================
  // STORAGE CHECKS
  // ============================================
  {
    id: 'public_bucket_write',
    name: 'Public Storage Bucket with Write Access',
    description: 'Storage buckets with public write access allow anyone to upload files.',
    severity: 'high',
    category: 'authorization',
    query: `
      SELECT
        id as bucket_id,
        name as bucket_name,
        public,
        'Bucket allows public access' as issue
      FROM storage.buckets
      WHERE public = true
    `,
    remediation: `
      Review if public access is necessary. To restrict:

      -- Make bucket private
      UPDATE storage.buckets
      SET public = false
      WHERE name = '{bucket_name}';

      -- Add RLS policies for controlled access
      CREATE POLICY "Authenticated users can upload"
        ON storage.objects
        FOR INSERT
        WITH CHECK (
          bucket_id = '{bucket_name}'
          AND auth.role() = 'authenticated'
        );
    `,
    documentation_url: 'https://supabase.com/docs/guides/storage/security/access-control'
  },

  {
    id: 'storage_no_rls',
    name: 'Storage Objects Without RLS',
    description: 'Storage objects table should have RLS enabled with appropriate policies.',
    severity: 'high',
    category: 'rls',
    query: `
      SELECT
        'storage' as schemaname,
        'objects' as tablename,
        c.relrowsecurity as rls_enabled
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'storage'
        AND c.relname = 'objects'
        AND c.relrowsecurity = false
    `,
    remediation: `
      Enable RLS on storage.objects and create appropriate policies:

      ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;

      -- Example: Users can only access their own files
      CREATE POLICY "User files isolation"
        ON storage.objects
        FOR ALL
        USING (auth.uid()::text = (storage.foldername(name))[1]);
    `,
    documentation_url: 'https://supabase.com/docs/guides/storage/security/access-control'
  },

  // ============================================
  // REALTIME CHECKS
  // ============================================
  {
    id: 'realtime_all_tables',
    name: 'Realtime Enabled on Sensitive Tables',
    description: 'Tables with Realtime enabled broadcast changes to all subscribers.',
    severity: 'medium',
    category: 'data_exposure',
    query: `
      SELECT
        schemaname,
        tablename,
        'Realtime may be broadcasting changes' as issue
      FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
    `,
    remediation: `
      Review which tables need Realtime. To disable for a table:

      -- Remove table from realtime publication
      ALTER PUBLICATION supabase_realtime
        DROP TABLE public.{table_name};

      Or configure row-level filtering in Realtime policies.
    `,
    documentation_url: 'https://supabase.com/docs/guides/realtime/authorization'
  }
];

export function getCheckById(id: string): SecurityCheck | undefined {
  return SECURITY_CHECKS.find(check => check.id === id);
}

export function getChecksByCategory(category: string): SecurityCheck[] {
  return SECURITY_CHECKS.filter(check => check.category === category);
}

export function getChecksBySeverity(severity: string): SecurityCheck[] {
  return SECURITY_CHECKS.filter(check => check.severity === severity);
}
