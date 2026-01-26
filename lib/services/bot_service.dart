import 'dart:async';

import '../game/bot_logic.dart';
import '../game/game_state.dart';
import '../game/models.dart';
import 'supabase_service.dart';

/// Service die bot acties orchestreert voor disconnected spelers
class BotService {
  final String gameId;
  final SupabaseService _supabase;

  Timer? _checkTimer;
  bool _isProcessing = false;

  static const Duration _botCheckInterval = Duration(seconds: 5);
  static const Duration _disconnectTimeout = Duration(seconds: 60);

  BotService({
    required this.gameId,
  }) : _supabase = SupabaseService.instance;

  /// Start de bot service - controleert periodiek of bots moeten ingrijpen
  void start() {
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(_botCheckInterval, (_) => _checkForBotActions());
  }

  /// Stop de bot service
  void stop() {
    _checkTimer?.cancel();
    _checkTimer = null;
  }

  /// Check of er spelers zijn die door een bot moeten worden overgenomen
  Future<void> _checkForBotActions() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final state = await _supabase.getGameState(gameId);
      if (state == null) return;

      // Skip als het spel niet actief is
      if (state.phase == GamePhase.lobby ||
          state.phase == GamePhase.gameEnd ||
          state.phase == GamePhase.roundEnd) {
        return;
      }

      // Haal speler info op uit database voor last_seen_at
      final dbPlayers = await _supabase.getPlayersWithLastSeen(gameId);

      // Update bot status in state
      _updateBotStatus(state, dbPlayers);

      // Check of huidige speler door bot moet worden gespeeld
      final currentPlayer = state.currentPlayer;
      final dbCurrentPlayer = dbPlayers.firstWhere(
        (p) => p.id == currentPlayer.id,
        orElse: () => currentPlayer,
      );

      if (_shouldBotPlay(dbCurrentPlayer)) {
        await _performBotAction(state, currentPlayer);
      }
    } catch (e) {
      // Silently handle errors - bot service mag niet crashen
    } finally {
      _isProcessing = false;
    }
  }

  /// Update bot controlled status gebaseerd op last seen timestamps
  void _updateBotStatus(GameState state, List<Player> dbPlayers) {
    final now = DateTime.now();

    for (final player in state.players) {
      final dbPlayer = dbPlayers.firstWhere(
        (p) => p.id == player.id,
        orElse: () => player,
      );

      player.isBotControlled = _shouldBotPlay(dbPlayer);
      player.lastSeenAt = dbPlayer.lastSeenAt;
    }
  }

  /// Bepaal of bot moet spelen voor deze speler
  bool _shouldBotPlay(Player player) {
    if (player.lastSeenAt == null) return false;

    final timeSinceLastSeen = DateTime.now().difference(player.lastSeenAt!);
    return timeSinceLastSeen > _disconnectTimeout;
  }

  /// Voer een bot actie uit voor de huidige speler
  Future<void> _performBotAction(GameState state, Player player) async {
    if (state.phase == GamePhase.bidding) {
      await _placeBotBid(state, player);
    } else if (state.phase == GamePhase.playing) {
      await _playBotCard(state, player);
    }
  }

  /// Plaats een bod als bot
  Future<void> _placeBotBid(GameState state, Player player) async {
    final bid = BotLogic.calculateBid(
      hand: player.hand,
      trump: state.trump,
      allowedBids: state.allowedBids,
    );

    await _supabase.placeBidAsBot(gameId, player.id, bid);
  }

  /// Speel een kaart als bot
  Future<void> _playBotCard(GameState state, Player player) async {
    final card = BotLogic.chooseCard(
      player: player,
      trump: state.trump,
      leadSuit: state.currentTrick?.leadSuit,
      currentTrickCards: state.currentTrick?.cards ?? [],
      targetTricks: player.bid ?? 0,
      tricksTaken: player.tricksTaken,
    );

    await _supabase.playCardAsBot(gameId, player.id, card);
  }
}
