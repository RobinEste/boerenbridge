import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../game/game_comments.dart';
import '../game/game_state.dart';
import '../game/models.dart' as models;
import '../providers/chat_provider.dart';
import '../providers/game_provider.dart';
import '../services/connection_service.dart';
import '../theme/app_colors.dart';
import '../widgets/app_logo.dart';
import '../widgets/connection_overlay.dart';
import '../widgets/game_chat_widget.dart';

class GameScreen extends ConsumerStatefulWidget {
  final String gameId;

  const GameScreen({super.key, required this.gameId});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  // Pauze states voor het tonen van resultaten
  bool _showBidSummary = false;
  bool _showTrickResult = false;
  Timer? _pauseTimer;

  // Track vorige state om veranderingen te detecteren
  models.Trick? _completedTrickToShow;
  String? _lastShownTrickId; // Unieke ID van de laatst getoonde slag

  @override
  void initState() {
    super.initState();
    // Laad het spel
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(gameProvider.notifier).loadGame(widget.gameId);
    });
  }

  /// Initialiseer chat wanneer we player ID hebben
  void _initializeChatIfNeeded(String? playerId) {
    if (playerId != null) {
      ref.read(chatProvider.notifier).initialize(widget.gameId, playerId);
    }
  }

  @override
  void dispose() {
    _pauseTimer?.cancel();
    ref.read(chatProvider.notifier).cleanup();
    super.dispose();
  }

  // Pauze duur voor overlays (bid samenvatting, slag resultaat)
  static const Duration _pauseDuration = Duration(seconds: 5);

  void _startPauseTimer(VoidCallback onComplete) {
    _pauseTimer?.cancel();
    _pauseTimer = Timer(_pauseDuration, () {
      if (mounted) {
        onComplete();
      }
    });
  }

  void _dismissBidSummary() {
    _pauseTimer?.cancel();
    setState(() {
      _showBidSummary = false;
    });
  }

  void _dismissTrickResult() {
    _pauseTimer?.cancel();
    setState(() {
      _showTrickResult = false;
      _completedTrickToShow = null;
    });
  }

  void _leaveGame() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Spel verlaten?'),
        content: const Text('Weet je zeker dat je het spel wilt verlaten?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Annuleren'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(gameProvider.notifier).leaveGame();
              context.go('/');
            },
            child: const Text('Verlaten'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gameState = ref.watch(gameProvider);

    // Toon errors
    ref.listen<GameProviderState>(gameProvider, (previous, next) {
      if (next.error != null && next.error != previous?.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error!),
            backgroundColor: theme.colorScheme.error,
          ),
        );
      }

      // Detecteer wanneer bieden net klaar is
      final prevGame = previous?.gameState;
      final nextGame = next.gameState;
      if (prevGame != null && nextGame != null) {
        // Check of we net van bidding naar playing zijn gegaan
        if (prevGame.phase == GamePhase.bidding &&
            nextGame.phase == GamePhase.playing &&
            !_showBidSummary) {
          setState(() {
            _showBidSummary = true;
          });
          _startPauseTimer(_dismissBidSummary);
        }

        // Check of er net een slag is voltooid
        if (nextGame.phase == GamePhase.playing) {
          final completedTrick = nextGame.completedTrick;

          // Maak unieke ID voor deze slag (gebaseerd op de kaarten)
          String? trickId;
          if (completedTrick != null && completedTrick.cards.length == nextGame.players.length) {
            trickId = completedTrick.cards.map((pc) => '${pc.playerId}:${pc.card}').join(',');
          }

          // Als er een voltooide slag is die we nog niet hebben getoond
          if (trickId != null &&
              trickId != _lastShownTrickId &&
              !_showTrickResult) {
            setState(() {
              _showTrickResult = true;
              _completedTrickToShow = completedTrick;
              _lastShownTrickId = trickId;
            });
            _startPauseTimer(_dismissTrickResult);
          }
        }

        // Reset tracking bij nieuwe ronde
        if (prevGame.phase != GamePhase.bidding && nextGame.phase == GamePhase.bidding) {
          _lastShownTrickId = null;
        }
      }
    });

    if (gameState.isLoading && gameState.gameState == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Spel laden...',
                style: theme.textTheme.bodyLarge,
              ),
            ],
          ),
        ),
      );
    }

    if (gameState.error != null && gameState.gameState == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                gameState.error!,
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => context.go('/'),
                child: const Text('Terug naar home'),
              ),
            ],
          ),
        ),
      );
    }

    final game = gameState.gameState;
    if (game == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Haal huidige speler op voor chat
    final currentPlayer = ref.watch(currentPlayerProvider);

    // Initialiseer chat als we een player ID hebben
    if (currentPlayer != null) {
      _initializeChatIfNeeded(currentPlayer.id);
    }

    final connectionService = gameState.connectionService;

    // Bepaal of chat button getoond moet worden (niet tijdens overlays)
    final showChatButton = currentPlayer != null &&
        !_showBidSummary &&
        !_showTrickResult &&
        game.phase != GamePhase.lobby;

    Widget scaffold = Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _leaveGame,
        ),
        title: Row(
          children: [
            const AppLogo(height: 40),
            Expanded(
              child: Text(
                _getPhaseTitle(game.phase),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.leaderboard),
            onPressed: () => _showScoreboard(context, game),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            _buildGameContent(context, game, gameState.isMyTurn),
            // Overlay voor bod samenvatting
            if (_showBidSummary)
              _buildBidSummaryOverlay(context, game),
            // Overlay voor slag resultaat
            if (_showTrickResult && _completedTrickToShow != null)
              _buildTrickResultOverlay(context, game, _completedTrickToShow!),
            // Chat button
            if (showChatButton)
              Positioned(
                bottom: 16,
                right: 16,
                child: ChatFloatingButton(
                  gameId: widget.gameId,
                  playerId: currentPlayer.id,
                ),
              ),
          ],
        ),
      ),
    );

    // Wrap met connection overlay als service beschikbaar is
    if (connectionService != null) {
      return ConnectionOverlay(
        connectionService: connectionService,
        stateStream: connectionService.stateStream,
        onCancel: () {
          ref.read(gameProvider.notifier).leaveGame();
          context.go('/');
        },
        child: scaffold,
      );
    }

    return scaffold;
  }

  Widget _buildBidSummaryOverlay(BuildContext context, GameState game) {
    final theme = Theme.of(context);

    return Container(
      color: AppColors.warmBrown.withValues(alpha: 0.6),
      child: Center(
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.gavel,
                  size: 48,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Alle biedingen binnen!',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                // Toon alle biedingen
                ...game.players.map((player) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 100,
                        child: Text(
                          player.name,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${player.bid ?? 0}',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
                const SizedBox(height: 16),
                // Totaal vs kaarten
                Builder(
                  builder: (context) {
                    final bidDiff = game.totalBidsSoFar - game.cardsThisRound;
                    final teamComment = GameComments.getTeamComment(bidDifference: bidDiff);

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: bidDiff == 0
                            ? Colors.orange.withValues(alpha: 0.2)
                            : bidDiff > 0
                                ? Colors.red.withValues(alpha: 0.2)
                                : Colors.blue.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Totaal: ${game.totalBidsSoFar} / ${game.cardsThisRound} kaarten',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (teamComment != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              teamComment,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontStyle: FontStyle.italic,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _dismissBidSummary,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start met spelen'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrickResultOverlay(BuildContext context, GameState game, models.Trick trick) {
    final theme = Theme.of(context);
    final winnerId = trick.winnerId;
    final winner = winnerId != null
        ? game.players.firstWhere((p) => p.id == winnerId)
        : null;

    return Container(
      color: AppColors.warmBrown.withValues(alpha: 0.6),
      child: Center(
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Slag compleet!',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 24),
                // Toon de gespeelde kaarten
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: trick.cards.map((pc) {
                    final player = game.players.firstWhere((p) => p.id == pc.playerId);
                    final isWinner = pc.playerId == winnerId;
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          decoration: isWinner
                              ? BoxDecoration(
                                  border: Border.all(color: Colors.green, width: 3),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.green.withValues(alpha: 0.4),
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                )
                              : null,
                          child: _buildCard(pc.card, large: true),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          player.name,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: isWinner ? FontWeight.bold : null,
                            color: isWinner ? Colors.green : null,
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                if (winner != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.emoji_events, color: Colors.green),
                        const SizedBox(width: 8),
                        Text(
                          '${winner.name} wint!',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _dismissTrickResult,
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Doorgaan'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getPhaseTitle(GamePhase phase) {
    return switch (phase) {
      GamePhase.lobby => 'Wachtkamer',
      GamePhase.bidding => 'Bieden',
      GamePhase.playing => 'Spelen',
      GamePhase.roundEnd => 'Ronde klaar',
      GamePhase.gameEnd => 'Spel afgelopen',
    };
  }

  Widget _buildGameContent(BuildContext context, GameState game, bool isMyTurn) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Info bar
          _buildInfoBar(context, game),
          const SizedBox(height: 16),

          // Main content based on phase
          Expanded(
            child: switch (game.phase) {
              GamePhase.bidding => _buildBiddingPhase(context, game, isMyTurn),
              GamePhase.playing => _buildPlayingPhase(context, game, isMyTurn),
              GamePhase.roundEnd => _buildRoundEndPhase(context, game),
              GamePhase.gameEnd => _buildGameEndPhase(context, game),
              _ => const Center(child: Text('Onbekende fase')),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBar(BuildContext context, GameState game) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            // Troef
            Column(
              children: [
                Text('Troef', style: theme.textTheme.labelSmall),
                const SizedBox(height: 4),
                Text(
                  game.trump?.symbol ?? '-',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: game.trump?.isRed == true ? Colors.red : Colors.black,
                  ),
                ),
              ],
            ),
            // Ronde
            Column(
              children: [
                Text('Ronde', style: theme.textTheme.labelSmall),
                const SizedBox(height: 4),
                Text(
                  '${game.currentRoundIndex + 1}/${game.rounds.length}',
                  style: theme.textTheme.titleLarge,
                ),
              ],
            ),
            // Kaarten
            Column(
              children: [
                Text('Kaarten', style: theme.textTheme.labelSmall),
                const SizedBox(height: 4),
                Text(
                  '${game.cardsThisRound}',
                  style: theme.textTheme.titleLarge,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBiddingPhase(BuildContext context, GameState game, bool isMyTurn) {
    final theme = Theme.of(context);
    final allowedBids = ref.watch(allowedBidsProvider);
    final currentPlayer = ref.watch(currentPlayerProvider);

    return Column(
      children: [
        // Wie is aan de beurt
        Card(
          color: isMyTurn ? theme.colorScheme.primaryContainer : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isMyTurn ? Icons.arrow_forward : Icons.hourglass_empty,
                  color: isMyTurn ? theme.colorScheme.onPrimaryContainer : null,
                ),
                const SizedBox(width: 8),
                Text(
                  isMyTurn ? 'Jouw beurt om te bieden!' : '${game.currentPlayer.name} is aan de beurt',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: isMyTurn ? theme.colorScheme.onPrimaryContainer : null,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Totaal geboden indicator
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Totaal geboden: ', style: theme.textTheme.bodyMedium),
                Text(
                  '${game.totalBidsSoFar}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(' / ${game.cardsThisRound} kaarten', style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Biedingen overzicht
        Expanded(
          child: Card(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: game.players.length,
              itemBuilder: (context, index) {
                final player = game.players[index];
                final hasBid = player.bid != null;

                return ListTile(
                  leading: _buildPlayerAvatar(theme, player, hasBid),
                  title: Row(
                    children: [
                      Text(player.name),
                      if (player.isBotControlled) ...[
                        const SizedBox(width: 8),
                        _buildBotBadge(theme),
                      ],
                    ],
                  ),
                  trailing: hasBid
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            '${player.bid}',
                            style: TextStyle(
                              color: theme.colorScheme.onPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      : Text(
                          'Wacht...',
                          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                        ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Toon hand tijdens bieden
        if (currentPlayer != null) ...[
          Text('Jouw hand (${currentPlayer.hand.length} kaarten):', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: currentPlayer.hand.map((card) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _buildCard(card),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Instructie voor nieuwe spelers (eerste 3 rondes)
        if (isMyTurn && currentPlayer != null && allowedBids.isNotEmpty && game.currentRoundIndex < 3)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              children: [
                Text(
                  'Kies je bod',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                Icon(
                  Icons.arrow_downward,
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
              ],
            ),
          ),

        // Bied knoppen
        if (isMyTurn && currentPlayer != null && allowedBids.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: allowedBids.map((bid) {
              return FilledButton(
                onPressed: () {
                  ref.read(gameProvider.notifier).placeBid(bid);
                },
                child: Text('$bid'),
              );
            }).toList(),
          )
        else if (isMyTurn)
          Text('Geen biedingen beschikbaar (allowedBids is leeg)', style: TextStyle(color: Colors.red)),
      ],
    );
  }

  Widget _buildPlayingPhase(BuildContext context, GameState game, bool isMyTurn) {
    final theme = Theme.of(context);
    final currentPlayer = ref.watch(currentPlayerProvider);
    final playableCards = ref.watch(playableCardsProvider);

    return Column(
      children: [
        // Status balk: over/onderbod + jouw bod/slagen
        _buildPlayingStatusBar(context, game, currentPlayer),
        const SizedBox(height: 8),

        // Wie is aan de beurt
        Card(
          color: isMyTurn ? theme.colorScheme.primaryContainer : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isMyTurn ? Icons.arrow_forward : Icons.hourglass_empty,
                  color: isMyTurn ? theme.colorScheme.onPrimaryContainer : null,
                ),
                const SizedBox(width: 8),
                Text(
                  isMyTurn ? 'Jouw beurt!' : '${game.currentPlayer.name} is aan de beurt',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: isMyTurn ? theme.colorScheme.onPrimaryContainer : null,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Huidige slag
        Expanded(
          child: Card(
            child: Center(
              child: _buildCurrentTrickView(context, game),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Mijn hand
        if (currentPlayer != null) ...[
          Text('Jouw hand (${currentPlayer.hand.length} kaarten):', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: currentPlayer.hand.map((card) {
                final canPlay = playableCards.contains(card);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Opacity(
                    opacity: isMyTurn && canPlay ? 1.0 : 0.5,
                    child: GestureDetector(
                      onTap: isMyTurn && canPlay
                          ? () => ref.read(gameProvider.notifier).playCard(card)
                          : null,
                      child: _buildCard(card),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPlayingStatusBar(BuildContext context, GameState game, models.Player? currentPlayer) {
    final theme = Theme.of(context);
    final bidDiff = game.bidDifference;
    final bidStatusColor = bidDiff > 0
        ? Colors.orange
        : bidDiff < 0
            ? Colors.blue
            : Colors.green;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Over/onderbod status
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: bidStatusColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                game.bidStatusText,
                style: TextStyle(
                  color: bidStatusColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
            // Jouw bod en slagen
            if (currentPlayer != null)
              Row(
                children: [
                  Text('Bod: ', style: theme.textTheme.bodySmall),
                  Text(
                    '${currentPlayer.bid ?? "-"}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Text('Gehaald: ', style: theme.textTheme.bodySmall),
                  Text(
                    '${currentPlayer.tricksTaken}/${currentPlayer.bid ?? 0}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: currentPlayer.tricksTaken == currentPlayer.bid
                          ? Colors.green
                          : currentPlayer.tricksTaken > (currentPlayer.bid ?? 0)
                              ? Colors.red
                              : null,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentTrickView(BuildContext context, GameState game) {
    final theme = Theme.of(context);

    if (game.currentTrick?.cards.isEmpty ?? true) {
      return Text(
        'Wacht op eerste kaart...',
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Wrap(
      spacing: 8,
      children: game.currentTrick!.cards.map((pc) {
        final player = game.players.firstWhere((p) => p.id == pc.playerId);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildCard(pc.card, large: true),
            const SizedBox(height: 4),
            Text(player.name, style: theme.textTheme.labelSmall),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildCard(models.Card card, {bool large = false}) {
    // 20% groter: 60 → 72 (normaal), 80 → 96 (large)
    final size = large ? 96.0 : 72.0;
    final fontSize = large ? 28.0 : 22.0;

    // Safely get the card text
    String cardText;
    Color cardColor;
    try {
      cardText = '${card.rank.symbol}${card.suit.symbol}';
      cardColor = card.suit.isRed ? AppColors.cardSuitRed : AppColors.cardSuitBlack;
    } catch (e) {
      cardText = '?';
      cardColor = Colors.grey;
    }

    return Container(
      width: size * 0.7,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.cardWhite,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.cardBorderWarm, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: AppColors.warmBrown.withValues(alpha: 0.15),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Center(
        child: Text(
          cardText,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            color: cardColor,
          ),
        ),
      ),
    );
  }

  /// Bouw een speler avatar met optioneel bot icoon
  Widget _buildPlayerAvatar(ThemeData theme, models.Player player, bool isActive) {
    return Stack(
      children: [
        CircleAvatar(
          backgroundColor: isActive
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          child: Text(
            player.name[0].toUpperCase(),
            style: TextStyle(
              color: isActive
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (player.isBotControlled)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                color: Colors.orange,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.smart_toy,
                size: 12,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }

  /// Bouw een bot badge label
  Widget _buildBotBadge(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange, width: 1),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.smart_toy, size: 12, color: Colors.orange),
          SizedBox(width: 4),
          Text(
            'BOT',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoundEndPhase(BuildContext context, GameState game) {
    final theme = Theme.of(context);

    // Sorteer spelers op totaalscore voor weergave
    final sortedPlayers = [...game.players]
      ..sort((a, b) => b.totalScore.compareTo(a.totalScore));

    // Bereken ronde scores voor winnaar/verliezer bepaling
    final roundScores = <String, int>{};
    for (final player in game.players) {
      roundScores[player.id] = game.rules.calculateRoundScore(
        player.bid!,
        player.tricksTaken,
      );
    }
    final maxRoundScore = roundScores.values.reduce((a, b) => a > b ? a : b);
    final minRoundScore = roundScores.values.reduce((a, b) => a < b ? a : b);

    // Team comment gebaseerd op bid difference
    final teamComment = GameComments.getTeamComment(
      bidDifference: game.bidDifference,
    );

    return Column(
      children: [
        Text(
          'Ronde ${game.currentRoundIndex + 1} klaar!',
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        // Over/onderbod status met optionele team comment
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: game.bidDifference > 0
                ? Colors.orange.withValues(alpha: 0.2)
                : game.bidDifference < 0
                    ? Colors.blue.withValues(alpha: 0.2)
                    : Colors.green.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Text(
                game.bidStatusText,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: game.bidDifference > 0
                      ? Colors.orange
                      : game.bidDifference < 0
                          ? Colors.blue
                          : Colors.green,
                ),
              ),
              if (teamComment != null) ...[
                const SizedBox(height: 4),
                Text(
                  teamComment,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Card(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: sortedPlayers.length,
              itemBuilder: (context, index) {
                final player = sortedPlayers[index];
                final correct = player.bid == player.tricksTaken;
                final roundScore = roundScores[player.id]!;
                final isRoundWinner = roundScore == maxRoundScore;
                final isRoundLoser = roundScore == minRoundScore && maxRoundScore != minRoundScore;

                // Haal grappige opmerking voor deze speler
                final comment = GameComments.getPlayerRoundComment(
                  bid: player.bid!,
                  tricksTaken: player.tricksTaken,
                  roundScore: roundScore,
                  isRoundWinner: isRoundWinner,
                  isRoundLoser: isRoundLoser,
                  totalPlayers: game.players.length,
                );

                return ListTile(
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${index + 1}.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        correct ? Icons.check_circle : Icons.cancel,
                        color: correct ? Colors.green : Colors.red,
                        size: 20,
                      ),
                    ],
                  ),
                  title: Text(player.name),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Bod: ${player.bid} | Gehaald: ${player.tricksTaken}'),
                      if (comment != null)
                        Text(
                          comment,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontStyle: FontStyle.italic,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                    ],
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${roundScore >= 0 ? '+' : ''}$roundScore',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: roundScore >= 0 ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Totaal: ${player.totalScore}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => ref.read(gameProvider.notifier).nextRound(),
          icon: const Icon(Icons.arrow_forward),
          label: Text(game.isLastRound ? 'Bekijk eindstand' : 'Volgende ronde'),
        ),
      ],
    );
  }

  Widget _buildGameEndPhase(BuildContext context, GameState game) {
    final theme = Theme.of(context);
    final sortedPlayers = [...game.players]
      ..sort((a, b) => b.totalScore.compareTo(a.totalScore));

    // Bereken marge tussen winnaar en tweede
    final winnerScore = sortedPlayers.isNotEmpty ? sortedPlayers[0].totalScore : 0;
    final secondScore = sortedPlayers.length > 1 ? sortedPlayers[1].totalScore : 0;
    final winnerMargin = winnerScore - secondScore;

    // Marge comment voor winnaar
    final marginComment = GameComments.getWinnerMarginComment(margin: winnerMargin);

    return Column(
      children: [
        Icon(
          Icons.emoji_events,
          size: 64,
          color: Colors.amber,
        ),
        const SizedBox(height: 8),
        Text(
          'Spel afgelopen!',
          style: theme.textTheme.headlineSmall,
        ),
        if (marginComment != null) ...[
          const SizedBox(height: 4),
          Text(
            marginComment,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontStyle: FontStyle.italic,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Expanded(
          child: Card(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: sortedPlayers.length,
              itemBuilder: (context, index) {
                final player = sortedPlayers[index];
                final medal = index == 0
                    ? '🥇'
                    : index == 1
                        ? '🥈'
                        : index == 2
                            ? '🥉'
                            : '';

                // Haal grappige opmerking voor eindstand
                final comment = GameComments.getPlayerGameEndComment(
                  rank: index,
                  totalScore: player.totalScore,
                  winnerScore: winnerScore,
                  totalPlayers: sortedPlayers.length,
                );

                return ListTile(
                  leading: Text(
                    medal.isNotEmpty ? medal : '${index + 1}.',
                    style: theme.textTheme.headlineMedium,
                  ),
                  title: Text(
                    player.name,
                    style: index == 0 ? const TextStyle(fontWeight: FontWeight.bold) : null,
                  ),
                  subtitle: comment != null
                      ? Text(
                          comment,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontStyle: FontStyle.italic,
                            color: theme.colorScheme.primary,
                          ),
                        )
                      : null,
                  trailing: Text(
                    '${player.totalScore}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => context.go('/'),
          icon: const Icon(Icons.home),
          label: const Text('Terug naar home'),
        ),
      ],
    );
  }

  void _showScoreboard(BuildContext context, GameState game) {
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Scorebord',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ...game.players.map((player) => ListTile(
                  leading: CircleAvatar(
                    child: Text(player.name[0].toUpperCase()),
                  ),
                  title: Text(player.name),
                  trailing: Text(
                    '${player.totalScore}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Sluiten'),
            ),
          ],
        ),
      ),
    );
  }
}
