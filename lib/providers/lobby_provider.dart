import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game/models.dart';
import '../game/rules.dart';
import '../services/supabase_service.dart';

/// Lobby state
class LobbyState {
  final String? gameId;
  final String? joinCode;
  final List<Player> players;
  final bool isHost;
  final GameRules rules;
  final bool isLoading;
  final String? error;
  final bool gameStarted;

  const LobbyState({
    this.gameId,
    this.joinCode,
    this.players = const [],
    this.isHost = false,
    this.rules = GameRules.dutch,
    this.isLoading = false,
    this.error,
    this.gameStarted = false,
  });

  LobbyState copyWith({
    String? gameId,
    String? joinCode,
    List<Player>? players,
    bool? isHost,
    GameRules? rules,
    bool? isLoading,
    String? error,
    bool? gameStarted,
  }) {
    return LobbyState(
      gameId: gameId ?? this.gameId,
      joinCode: joinCode ?? this.joinCode,
      players: players ?? this.players,
      isHost: isHost ?? this.isHost,
      rules: rules ?? this.rules,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      gameStarted: gameStarted ?? this.gameStarted,
    );
  }
}

/// Lobby provider - beheert wachtkamer state
class LobbyNotifier extends StateNotifier<LobbyState> {
  LobbyNotifier() : super(const LobbyState());

  StreamSubscription<List<Player>>? _playersSubscription;
  StreamSubscription<bool>? _gameStartedSubscription;
  Timer? _pollTimer;

  /// Maak een nieuw spel aan
  Future<String?> createGame(String hostName, {GameRules? rules}) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final gameInfo = await SupabaseService.instance.createGame(
        hostName: hostName,
        rules: rules ?? GameRules.dutch,
      );

      // Subscribe op realtime updates
      SupabaseService.instance.subscribeToGame(gameInfo.gameId);
      _subscribeToPlayers();
      _subscribeToGameStarted();
      _startPolling();

      // Haal initiële spelers op
      final players = await SupabaseService.instance.getPlayers(gameInfo.gameId);

      state = LobbyState(
        gameId: gameInfo.gameId,
        joinCode: gameInfo.joinCode,
        isHost: true,
        rules: gameInfo.rules,
        players: players,
        isLoading: false,
      );

      return gameInfo.joinCode;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Kon spel niet aanmaken: $e',
      );
      return null;
    }
  }

  /// Join een bestaand spel
  Future<bool> joinGame(String joinCode, String playerName) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      print('DEBUG joinGame: Starting join for code $joinCode');
      final gameInfo = await SupabaseService.instance.joinGame(
        joinCode: joinCode,
        playerName: playerName,
      );

      if (gameInfo == null) {
        print('DEBUG joinGame: gameInfo is null');
        state = state.copyWith(
          isLoading: false,
          error: 'Spel niet gevonden of al gestart',
        );
        return false;
      }

      print('DEBUG joinGame: Got gameInfo with gameId=${gameInfo.gameId}');

      // Subscribe op realtime updates
      SupabaseService.instance.subscribeToGame(gameInfo.gameId);
      _subscribeToPlayers();
      _subscribeToGameStarted();
      _startPolling();

      // Haal initiële spelers op
      print('DEBUG joinGame: Fetching players for gameId=${gameInfo.gameId}');
      final players = await SupabaseService.instance.getPlayers(gameInfo.gameId);
      print('DEBUG joinGame: Got ${players.length} players: ${players.map((p) => p.name).toList()}');

      state = LobbyState(
        gameId: gameInfo.gameId,
        joinCode: joinCode,
        isHost: false,
        rules: gameInfo.rules,
        players: players,
        isLoading: false,
      );

      print('DEBUG joinGame: State updated with ${state.players.length} players');
      return true;
    } catch (e) {
      print('DEBUG joinGame: Error: $e');
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
      return false;
    }
  }

  /// Subscribe op realtime player updates
  void _subscribeToPlayers() {
    _playersSubscription?.cancel();
    _playersSubscription = SupabaseService.instance.playersStream.listen(
      (players) {
        state = state.copyWith(players: players);
      },
      onError: (e) {
        state = state.copyWith(error: 'Verbinding verloren: $e');
      },
    );
  }

  /// Subscribe op game started events
  void _subscribeToGameStarted() {
    _gameStartedSubscription?.cancel();
    _gameStartedSubscription = SupabaseService.instance.gameStartedStream.listen(
      (started) {
        print('DEBUG lobby_provider: Game started event received: $started');
        if (started) {
          state = state.copyWith(gameStarted: true);
        }
      },
      onError: (e) {
        print('DEBUG lobby_provider: Game started stream error: $e');
      },
    );
  }

  /// Start polling voor game status (backup voor realtime)
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (state.gameId == null) return;

      try {
        final status = await SupabaseService.instance.getGameStatus(state.gameId!);
        if (status == 'playing' && !state.gameStarted) {
          print('DEBUG lobby_provider: Polling detected game started');
          state = state.copyWith(gameStarted: true);
          _pollTimer?.cancel();
        }
      } catch (e) {
        print('DEBUG lobby_provider: Polling error: $e');
      }
    });
  }

  /// Start het spel (alleen voor host)
  Future<bool> startGame() async {
    if (!state.isHost || state.gameId == null) {
      state = state.copyWith(error: 'Alleen de host kan het spel starten');
      return false;
    }

    if (state.players.length < 2) {
      state = state.copyWith(error: 'Minimaal 2 spelers nodig');
      return false;
    }

    state = state.copyWith(isLoading: true, error: null);

    try {
      await SupabaseService.instance.startGame(state.gameId!);
      state = state.copyWith(isLoading: false, gameStarted: true);
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Kon spel niet starten: $e',
      );
      return false;
    }
  }

  /// Verlaat de lobby
  void leaveLobby() {
    _playersSubscription?.cancel();
    _gameStartedSubscription?.cancel();
    _pollTimer?.cancel();
    state = const LobbyState();
  }

  /// Clear error
  void clearError() {
    state = state.copyWith(error: null);
  }

  @override
  void dispose() {
    _playersSubscription?.cancel();
    _gameStartedSubscription?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }
}

/// Global lobby provider
final lobbyProvider = StateNotifierProvider<LobbyNotifier, LobbyState>((ref) {
  return LobbyNotifier();
});
