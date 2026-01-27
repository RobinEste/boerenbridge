import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'config.dart' show AppConfig;
import 'screens/home_screen.dart';
import 'screens/lobby_screen.dart';
import 'screens/game_screen.dart';
import 'screens/speluitleg_screen.dart';
import 'services/supabase_service.dart';
import 'theme/app_colors.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialiseer Supabase
  await SupabaseService.initialize(
    supabaseUrl: AppConfig.supabaseUrl,
    supabaseAnonKey: AppConfig.supabaseAnonKey,
  );

  runApp(
    const ProviderScope(
      child: BoerenbridgeApp(),
    ),
  );
}

/// Router configuratie
final _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      name: 'home',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/lobby/:joinCode',
      name: 'lobby',
      builder: (context, state) {
        final joinCode = state.pathParameters['joinCode']!;
        final isHost = state.extra as bool? ?? false;
        return LobbyScreen(joinCode: joinCode, isHost: isHost);
      },
    ),
    GoRoute(
      path: '/game/:gameId',
      name: 'game',
      builder: (context, state) {
        final gameId = state.pathParameters['gameId']!;
        return GameScreen(gameId: gameId);
      },
    ),
    GoRoute(
      path: '/speluitleg',
      name: 'speluitleg',
      builder: (context, state) {
        final variant = state.uri.queryParameters['variant'] ?? 'volledig';
        return SpeluitlegScreen(variant: variant);
      },
    ),
  ],
);

class BoerenbridgeApp extends StatelessWidget {
  const BoerenbridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      routerConfig: _router,
    );
  }

  ThemeData _buildTheme() {
    final baseTheme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.forestGreen, // Donkergroen - kaartspel thema
        brightness: Brightness.light,
      ),
    );

    return baseTheme.copyWith(
      scaffoldBackgroundColor: AppColors.warmOffWhite,
      textTheme: GoogleFonts.interTextTheme(baseTheme.textTheme),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        backgroundColor: AppColors.warmBeige,
        foregroundColor: baseTheme.colorScheme.onSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        filled: true,
        fillColor: AppColors.warmCream,
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        color: AppColors.warmBeige,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
        shadowColor: AppColors.warmBrown.withValues(alpha: 0.3),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.warmBeige,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.warmBeige,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }
}
