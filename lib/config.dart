class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  // App configuratie
  static const appName = 'Lekkerkaarten';
  static const minPlayers = 2;
  static const maxPlayers = 6;
}
