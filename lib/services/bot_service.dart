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

  // Bot feature toggle
  static const bool _botEnabled = false;

  BotService({
    required this.gameId,
  }) : _supabase = SupabaseService.instance;

  /// Start de bot service - controleert periodiek of bots moeten ingrijpen
  void start() {
    if (!_botEnabled) return; // Bot tijdelijk uitgeschakeld

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

      // NOOIT bot spelen voor de huidige gebruiker (die speelt zelf)
      final myUserId = _supabase.currentUserId;
      if (currentPlayer.isCurrentUser(myUserId)) {
        return;
      }

      final shouldPlay = _shouldBotPlay(dbCurrentPlayer);
      if (shouldPlay) {
        await _performBotAction(state, currentPlayer);
      }
    } catch (e) {
      // Silently handle errors - bot service mag niet crashen
    } finally {
      _isProcessing = false;
    }
  }

  // Referentie tijd van de server (meest recente heartbeat)
  DateTime? _serverTimeReference;

  /// Update bot controlled status gebaseerd op last seen timestamps
  void _updateBotStatus(GameState state, List<Player> dbPlayers) {
    // Bepaal server tijd referentie: de meest recente lastSeenAt van alle spelers
    // Dit voorkomt problemen met clock skew tussen client en server
    DateTime? mostRecentSeen;
    for (final p in dbPlayers) {
      if (p.lastSeenAt != null) {
        if (mostRecentSeen == null || p.lastSeenAt!.isAfter(mostRecentSeen)) {
          mostRecentSeen = p.lastSeenAt;
        }
      }
    }
    _serverTimeReference = mostRecentSeen;

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
    // Geen lastSeenAt = speler is nieuw of heartbeat nog niet gestart, GEEN bot
    if (player.lastSeenAt == null) return false;

    // Geen server referentie = kunnen niet vergelijken, GEEN bot
    if (_serverTimeReference == null) return false;

    // Gebruik de meest recente heartbeat als "nu" referentie
    // Dit voorkomt clock skew problemen tussen client en server
    final serverNow = _serverTimeReference!;
    final lastSeen = player.lastSeenAt!;
    final timeSinceLastSeen = serverNow.difference(lastSeen);

    // Als de speler de meest recente is, is het verschil 0 of zeer klein
    // Als de speler lang niet gezien is, is het verschil groot
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
