import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game/game_state.dart';
import '../game/models.dart' as models;
import '../services/supabase_service.dart';

/// Game provider state
class GameProviderState {
  final GameState? gameState;
  final bool isLoading;
  final String? error;
  final bool isMyTurn;

  const GameProviderState({
    this.gameState,
    this.isLoading = false,
    this.error,
    this.isMyTurn = false,
  });

  GameProviderState copyWith({
    GameState? gameState,
    bool? isLoading,
    String? error,
    bool? isMyTurn,
  }) {
    return GameProviderState(
      gameState: gameState ?? this.gameState,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      isMyTurn: isMyTurn ?? this.isMyTurn,
    );
  }
}

/// Game provider - beheert actieve spelstaat
class GameNotifier extends StateNotifier<GameProviderState> {
  GameNotifier() : super(const GameProviderState());

  StreamSubscription<GameState>? _gameSubscription;
  String? _currentGameId;

  /// Laad en subscribe op een spel
  Future<void> loadGame(String gameId) async {
    _currentGameId = gameId;
    state = state.copyWith(isLoading: true, error: null);

    try {
      // Subscribe op realtime updates
      SupabaseService.instance.subscribeToGame(gameId);

      _gameSubscription?.cancel();
      _gameSubscription = SupabaseService.instance.gameStateStream.listen(
        (gameState) {
          _updateGameState(gameState);
        },
        onError: (e) {
          state = state.copyWith(error: 'Verbinding verloren: $e');
        },
      );

      // Haal huidige state op
      final gameState = await SupabaseService.instance.getGameState(gameId);

      if (gameState != null) {
        _updateGameState(gameState);
      }

      state = state.copyWith(isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Kon spel niet laden: $e',
      );
    }
  }

  void _updateGameState(GameState gameState) {
    final myUserId = SupabaseService.instance.currentUserId;
    final isMyTurn = gameState.currentPlayer.isCurrentUser(myUserId);

    state = state.copyWith(
      gameState: gameState,
      isMyTurn: isMyTurn,
    );
  }

  /// Plaats een bod
  Future<bool> placeBid(int bid) async {
    if (_currentGameId == null) return false;

    state = state.copyWith(isLoading: true, error: null);

    try {
      await SupabaseService.instance.placeBid(_currentGameId!, bid);
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Kon bod niet plaatsen: $e',
      );
      return false;
    }
  }

  /// Speel een kaart
  Future<bool> playCard(models.Card card) async {
    if (_currentGameId == null) return false;

    state = state.copyWith(isLoading: true, error: null);

    try {
      await SupabaseService.instance.playCard(_currentGameId!, card);
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Kon kaart niet spelen: $e',
      );
      return false;
    }
  }

  /// Ga naar volgende ronde
  Future<bool> nextRound() async {
    if (_currentGameId == null) return false;

    state = state.copyWith(isLoading: true, error: null);

    try {
      await SupabaseService.instance.nextRound(_currentGameId!);
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Kon niet naar volgende ronde: $e',
      );
      return false;
    }
  }

  /// Verlaat het spel
  void leaveGame() {
    _gameSubscription?.cancel();
    _currentGameId = null;
    state = const GameProviderState();
  }

  /// Clear error
  void clearError() {
    state = state.copyWith(error: null);
  }

  @override
  void dispose() {
    _gameSubscription?.cancel();
    super.dispose();
  }
}

/// Global game provider
final gameProvider = StateNotifierProvider<GameNotifier, GameProviderState>((ref) {
  return GameNotifier();
});

/// Helper provider voor huidige speler info
final currentPlayerProvider = Provider<models.Player?>((ref) {
  final gameState = ref.watch(gameProvider).gameState;
  if (gameState == null) return null;

  final myUserId = SupabaseService.instance.currentUserId;
  try {
    return gameState.players.firstWhere((p) => p.isCurrentUser(myUserId));
  } catch (_) {
    return null;
  }
});

/// Helper provider voor speelbare kaarten
final playableCardsProvider = Provider<List<models.Card>>((ref) {
  final gameState = ref.watch(gameProvider).gameState;
  final currentPlayer = ref.watch(currentPlayerProvider);

  if (gameState == null || currentPlayer == null) return [];
  if (gameState.phase != GamePhase.playing) return [];

  final leadSuit = gameState.currentTrick?.leadSuit;
  return currentPlayer.playableCards(leadSuit);
});

/// Helper provider voor toegestane biedingen
final allowedBidsProvider = Provider<List<int>>((ref) {
  final gameState = ref.watch(gameProvider).gameState;
  if (gameState == null) return [];
  if (gameState.phase != GamePhase.bidding) return [];

  return gameState.allowedBids;
});
