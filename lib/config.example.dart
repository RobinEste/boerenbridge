// Supabase configuratie
//
// BELANGRIJK: Kopieer dit bestand naar config.dart en vul je eigen credentials in:
//   cp lib/config.example.dart lib/config.dart
//
// Het bestand config.dart staat in .gitignore en wordt niet gecommit.

class AppConfig {
  // Vind deze in Supabase Dashboard → Settings → API
  static const supabaseUrl = 'https://YOUR_PROJECT.supabase.co';
  static const supabaseAnonKey = 'YOUR_ANON_KEY';

  // App configuratie
  static const appName = 'Boerenbridge';
  static const minPlayers = 2;
  static const maxPlayers = 6;
}
