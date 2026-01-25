import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/supabase_service.dart';

/// Auth state met user ID en display naam
class AuthState {
  final String? userId;
  final String? displayName;
  final bool isLoading;
  final String? error;

  const AuthState({
    this.userId,
    this.displayName,
    this.isLoading = false,
    this.error,
  });

  bool get isAuthenticated => userId != null;

  AuthState copyWith({
    String? userId,
    String? displayName,
    bool? isLoading,
    String? error,
  }) {
    return AuthState(
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

/// Auth provider - beheert anonieme authenticatie en spelernaam
class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(const AuthState());

  static const _displayNameKey = 'player_display_name';

  /// Initialiseer auth state (laden van opgeslagen naam)
  Future<void> initialize() async {
    state = state.copyWith(isLoading: true);

    try {
      // Laad opgeslagen display naam
      final prefs = await SharedPreferences.getInstance();
      final savedName = prefs.getString(_displayNameKey);

      // Check of al ingelogd bij Supabase
      final currentUserId = SupabaseService.instance.currentUserId;

      state = AuthState(
        userId: currentUserId,
        displayName: savedName,
        isLoading: false,
      );
    } catch (e) {
      state = AuthState(
        isLoading: false,
        error: 'Kon authenticatie niet initialiseren: $e',
      );
    }
  }

  /// Sla display naam op en log anoniem in indien nodig
  Future<void> setDisplayName(String name) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      // Sla naam lokaal op
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_displayNameKey, name);

      // Log anoniem in als nog niet ingelogd
      String? userId = SupabaseService.instance.currentUserId;
      if (userId == null) {
        userId = await SupabaseService.instance.signInAnonymously();
      }

      state = AuthState(
        userId: userId,
        displayName: name,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Kon niet inloggen: $e',
      );
    }
  }

  /// Update alleen de display naam (voor settings)
  Future<void> updateDisplayName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_displayNameKey, name);
    state = state.copyWith(displayName: name);
  }

  /// Clear error state
  void clearError() {
    state = state.copyWith(error: null);
  }
}

/// Global auth provider
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});
