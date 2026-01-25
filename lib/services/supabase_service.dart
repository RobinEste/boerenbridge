// Supabase Service voor Boerenbridge
// Beheert alle communicatie met Supabase (auth, database, realtime)

import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../game/game_state.dart';
import '../game/models.dart';
import '../game/rules.dart';

// =============================================================================
// SUPABASE CLIENT SETUP
// =============================================================================

class SupabaseService {
  static SupabaseService? _instance;
  late final SupabaseClient _client;
  
  // Realtime subscriptions
  RealtimeChannel? _gameChannel;
  final _gameStateController = StreamController<GameState>.broadcast();
  final _playersController = StreamController<List<Player>>.broadcast();
  final _gameStartedController = StreamController<bool>.broadcast();
  
  SupabaseService._();
  
  static Future<SupabaseService> initialize({
    required String supabaseUrl,
    required String supabaseAnonKey,
  }) async {
    if (_instance != null) return _instance!;
    
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
    
    _instance = SupabaseService._();
    _instance!._client = Supabase.instance.client;
    return _instance!;
  }
  
  static SupabaseService get instance {
    if (_instance == null) {
      throw StateError('SupabaseService not initialized. Call initialize() first.');
    }
    return _instance!;
  }
  
  SupabaseClient get client => _client;
  
  // Streams voor UI
  Stream<GameState> get gameStateStream => _gameStateController.stream;
  Stream<List<Player>> get playersStream => _playersController.stream;
  Stream<bool> get gameStartedStream => _gameStartedController.stream;
  
  // ===========================================================================
  // AUTHENTICATION
  // ===========================================================================
  
  /// Anoniem inloggen (voor guests)
  Future<String> signInAnonymously() async {
    final response = await _client.auth.signInAnonymously();
    return response.user?.id ?? '';
  }
  
  /// Huidige user ID
  String? get currentUserId => _client.auth.currentUser?.id;
  
  /// Check of user is ingelogd
  bool get isAuthenticated => _client.auth.currentUser != null;
  
  // ===========================================================================
  // GAME MANAGEMENT
  // ===========================================================================
  
  /// Maak een nieuw spel aan
  Future<GameInfo> createGame({
    required GameRules rules,
    required String hostName,
  }) async {
    // Zorg dat we ingelogd zijn
    if (!isAuthenticated) {
      await signInAnonymously();
    }

    // Maak game aan
    final gameResponse = await _client
        .from('games')
        .insert({
          'rules': rules.toJson(),
          'host_id': currentUserId,
        })
        .select()
        .single();

    final gameId = gameResponse['id'] as String;
    final joinCode = gameResponse['join_code'] as String;

    // Voeg host toe als eerste speler
    await _addPlayer(gameId, hostName, seatPosition: 0);

    return GameInfo(
      gameId: gameId,
      joinCode: joinCode,
      rules: rules,
    );
  }
  
  /// Join een bestaand spel via code
  Future<GameInfo?> joinGame({
    required String joinCode,
    required String playerName,
  }) async {
    print('DEBUG joinGame service: Starting join for code=$joinCode, player=$playerName');
    // Zorg dat we ingelogd zijn
    if (!isAuthenticated) {
      print('DEBUG joinGame service: Not authenticated, signing in anonymously');
      await signInAnonymously();
    }
    print('DEBUG joinGame service: currentUserId=$currentUserId');

    // Vind het spel
    final gameResponse = await _client
        .from('games')
        .select()
        .eq('join_code', joinCode.toUpperCase())
        .eq('status', 'waiting')
        .maybeSingle();

    print('DEBUG joinGame service: gameResponse=$gameResponse');
    if (gameResponse == null) {
      return null; // Game niet gevonden of al gestart
    }

    final gameId = gameResponse['id'] as String;
    print('DEBUG joinGame service: gameId=$gameId');
    
    // Tel huidige spelers
    final playersResponse = await _client
        .from('game_players')
        .select('seat_position')
        .eq('game_id', gameId)
        .isFilter('left_at', null);
    
    final currentPlayers = playersResponse as List;
    if (currentPlayers.length >= 6) {
      throw Exception('Spel is vol (max 6 spelers)');
    }
    
    // Bepaal seat position
    final takenSeats = currentPlayers
        .map((p) => p['seat_position'] as int)
        .toSet();
    final nextSeat = List.generate(6, (i) => i)
        .firstWhere((i) => !takenSeats.contains(i));
    
    // Voeg speler toe
    print('DEBUG joinGame service: Adding player at seat $nextSeat');
    await _addPlayer(gameId, playerName, seatPosition: nextSeat);
    print('DEBUG joinGame service: Player added successfully');

    return GameInfo(
      gameId: gameId,
      joinCode: joinCode,
      rules: GameRules.fromJson(gameResponse['rules'] as Map<String, dynamic>),
    );
  }
  
  Future<void> _addPlayer(String gameId, String name, {required int seatPosition}) async {
    print('DEBUG _addPlayer: gameId=$gameId, name=$name, seat=$seatPosition, userId=$currentUserId');
    await _client.from('game_players').insert({
      'game_id': gameId,
      'user_id': currentUserId,
      'display_name': name,
      'seat_position': seatPosition,
    });
    print('DEBUG _addPlayer: Insert completed');
  }
  
  /// Start het spel (alleen host)
  Future<void> startGame(String gameId) async {
    // Haal spelers op
    final playersResponse = await _client
        .from('game_players')
        .select()
        .eq('game_id', gameId)
        .isFilter('left_at', null)
        .order('seat_position');
    
    final players = (playersResponse as List).map((p) => Player(
      id: p['id'] as String,
      odataId: p['user_id'] as String?,
      name: p['display_name'] as String,
    )).toList();
    
    if (players.length < 2) {
      throw Exception('Minimaal 2 spelers nodig');
    }
    
    // Haal rules op
    final gameResponse = await _client
        .from('games')
        .select('rules')
        .eq('id', gameId)
        .single();
    
    final rules = GameRules.fromJson(gameResponse['rules'] as Map<String, dynamic>);
    
    // Maak game state
    final state = GameState(
      gameId: gameId,
      rules: rules,
      players: players,
    );
    state.startGame();
    
    // Update database
    await _client.from('games').update({
      'status': 'playing',
      'started_at': DateTime.now().toIso8601String(),
    }).eq('id', gameId);
    
    await _updateGameState(gameId, state);
  }
  
  // ===========================================================================
  // GAME ACTIONS
  // ===========================================================================
  
  /// Plaats een bod
  Future<void> placeBid(String gameId, int bid) async {
    await _performAction(gameId, (state) {
      final playerId = _getMyPlayerId(state);
      state.placeBid(playerId, bid);
    }, actionType: 'bid', payload: {'bid': bid});
  }
  
  /// Speel een kaart
  Future<void> playCard(String gameId, Card card) async {
    await _performAction(gameId, (state) {
      final playerId = _getMyPlayerId(state);
      state.playCard(playerId, card);
    }, actionType: 'play_card', payload: {'card': card.toJson()});
  }
  
  /// Ga naar volgende ronde
  Future<void> nextRound(String gameId) async {
    await _performAction(gameId, (state) {
      state.nextRound();
    }, actionType: 'next_round');
  }
  
  String _getMyPlayerId(GameState state) {
    print('DEBUG _getMyPlayerId: Looking for userId=$currentUserId');
    print('DEBUG _getMyPlayerId: Players in state:');
    for (final p in state.players) {
      print('  - ${p.name}: id=${p.id}, odataId=${p.odataId}');
    }

    final player = state.players.firstWhere(
      (p) => p.isCurrentUser(currentUserId),
      orElse: () => throw Exception('Speler niet gevonden in spel (userId=$currentUserId)'),
    );
    print('DEBUG _getMyPlayerId: Found player ${player.name}');
    return player.id;
  }
  
  Future<void> _performAction(
    String gameId,
    void Function(GameState) action, {
    required String actionType,
    Map<String, dynamic>? payload,
  }) async {
    print('DEBUG _performAction: Starting action=$actionType');

    // Haal huidige state op
    final stateResponse = await _client
        .from('game_state')
        .select()
        .eq('game_id', gameId)
        .single();

    final currentVersion = stateResponse['version'] as int;
    final state = GameState.fromJson(stateResponse['state'] as Map<String, dynamic>);
    print('DEBUG _performAction: Loaded state, version=$currentVersion, phase=${state.phase}, round=${state.currentRoundIndex}');

    // Voer actie uit
    action(state);
    print('DEBUG _performAction: After action, phase=${state.phase}, round=${state.currentRoundIndex}');
    if (state.players.isNotEmpty) {
      print('DEBUG _performAction: Player 0 hand has ${state.players[0].hand.length} cards');
    }

    // Update met optimistic locking
    final stateJson = state.toJson();
    print('DEBUG _performAction: Saving state to DB, json players[0].hand has ${((stateJson['players'] as List)[0]['hand'] as List).length} cards');

    final updateResponse = await _client
        .from('game_state')
        .update({
          'state': stateJson,
          'version': currentVersion + 1,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('game_id', gameId)
        .eq('version', currentVersion) // Optimistic lock
        .select();
    
    if ((updateResponse as List).isEmpty) {
      // Version mismatch - iemand anders was sneller
      throw ConcurrentModificationException();
    }
    
    // Log actie
    try {
      await _client.from('game_actions').insert({
        'game_id': gameId,
        'player_id': currentUserId,
        'action_type': actionType,
        'payload': payload,
        'state_version': currentVersion,
      });
    } catch (e) {
      print('DEBUG: game_actions insert failed: $e');
      // Actie logging mag niet de hoofdactie laten falen
    }
  }
  
  Future<void> _updateGameState(String gameId, GameState state) async {
    await _client
        .from('game_state')
        .update({
          'state': state.toJson(),
          'version': 1,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('game_id', gameId);
  }
  
  // ===========================================================================
  // REALTIME SUBSCRIPTIONS
  // ===========================================================================
  
  /// Subscribe op game updates
  void subscribeToGame(String gameId) {
    print('DEBUG subscribeToGame: Setting up subscription for gameId=$gameId');
    // Unsubscribe van vorige game
    _gameChannel?.unsubscribe();

    _gameChannel = _client
        .channel('game:$gameId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'game_state',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'game_id',
            value: gameId,
          ),
          callback: (payload) {
            print('DEBUG realtime: Received game_state update');
            final stateJson = payload.newRecord['state'] as Map<String, dynamic>;
            print('DEBUG realtime: phase=${stateJson['phase']}, round=${stateJson['current_round_index']}');
            final state = GameState.fromJson(stateJson);
            print('DEBUG realtime: After fromJson - phase=${state.phase}, players[0].hand.length=${state.players.isNotEmpty ? state.players[0].hand.length : 0}');
            _gameStateController.add(state);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'game_players',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'game_id',
            value: gameId,
          ),
          callback: (payload) {
            // Refresh players list
            _refreshPlayers(gameId);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'games',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: gameId,
          ),
          callback: (payload) {
            print('DEBUG: games table updated: ${payload.newRecord}');
            final status = payload.newRecord['status'] as String?;
            if (status == 'playing') {
              print('DEBUG: Game started! Notifying listeners');
              _gameStartedController.add(true);
            }
          },
        )
        .subscribe((status, error) {
          print('DEBUG subscribeToGame: Channel status=$status, error=$error');
        });
  }
  
  Future<void> _refreshPlayers(String gameId) async {
    final players = await getPlayers(gameId);
    _playersController.add(players);
  }

  /// Haal spelers op voor een game
  Future<List<Player>> getPlayers(String gameId) async {
    print('DEBUG getPlayers: Fetching for gameId=$gameId');
    final response = await _client
        .from('game_players')
        .select()
        .eq('game_id', gameId)
        .isFilter('left_at', null)
        .order('seat_position');

    print('DEBUG getPlayers: Raw response=$response');
    return (response as List).map((p) => Player(
      id: p['id'] as String,
      odataId: p['user_id'] as String?,
      name: p['display_name'] as String,
    )).toList();
  }
  
  /// Haal game status op (waiting, playing, finished)
  Future<String> getGameStatus(String gameId) async {
    final response = await _client
        .from('games')
        .select('status')
        .eq('id', gameId)
        .single();
    return response['status'] as String;
  }

  /// Haal huidige game state op
  Future<GameState?> getGameState(String gameId) async {
    final response = await _client
        .from('game_state')
        .select()
        .eq('game_id', gameId)
        .maybeSingle();
    
    if (response == null) return null;
    
    return GameState.fromJson(response['state'] as Map<String, dynamic>);
  }
  
  /// Unsubscribe van alles
  void dispose() {
    _gameChannel?.unsubscribe();
    _gameStateController.close();
    _playersController.close();
    _gameStartedController.close();
  }
}

// =============================================================================
// HELPER CLASSES
// =============================================================================

class GameInfo {
  final String gameId;
  final String joinCode;
  final GameRules rules;
  
  GameInfo({
    required this.gameId,
    required this.joinCode,
    required this.rules,
  });
}

class ConcurrentModificationException implements Exception {
  @override
  String toString() => 'Concurrent modification detected. Please retry.';
}
