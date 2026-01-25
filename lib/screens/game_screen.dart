import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../game/game_state.dart';
import '../game/models.dart' as models;
import '../providers/game_provider.dart';
import '../services/supabase_service.dart';

class GameScreen extends ConsumerStatefulWidget {
  final String gameId;

  const GameScreen({super.key, required this.gameId});

  @override
  ConsumerState<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends ConsumerState<GameScreen> {
  @override
  void initState() {
    super.initState();
    // Laad het spel
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(gameProvider.notifier).loadGame(widget.gameId);
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

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: _leaveGame,
        ),
        title: Text(_getPhaseTitle(game.phase)),
        actions: [
          IconButton(
            icon: const Icon(Icons.leaderboard),
            onPressed: () => _showScoreboard(context, game),
          ),
        ],
      ),
      body: SafeArea(
        child: _buildGameContent(context, game, gameState.isMyTurn),
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
                  leading: CircleAvatar(
                    backgroundColor: hasBid
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                    child: Text(
                      player.name[0].toUpperCase(),
                      style: TextStyle(
                        color: hasBid
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  title: Text(player.name),
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

        // Bied knoppen
        if (isMyTurn && currentPlayer != null && allowedBids.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: allowedBids.map((bid) {
              return FilledButton(
                onPressed: () {
                  print('DEBUG: Placing bid $bid');
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

    // Bepaal of we de voltooide slag moeten tonen
    final showCompletedTrick = game.completedTrick != null &&
        game.completedTrick!.cards.length == game.players.length;

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

        // Voltooide slag of huidige slag
        Expanded(
          child: Card(
            child: Center(
              child: showCompletedTrick
                  ? _buildCompletedTrickView(context, game)
                  : _buildCurrentTrickView(context, game),
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

  Widget _buildCompletedTrickView(BuildContext context, GameState game) {
    final theme = Theme.of(context);
    final winnerId = game.completedTrickWinnerId;
    final winner = winnerId != null
        ? game.players.firstWhere((p) => p.id == winnerId)
        : null;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Slag compleet!',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: game.completedTrick!.cards.map((pc) {
            final player = game.players.firstWhere((p) => p.id == pc.playerId);
            final isWinner = pc.playerId == winnerId;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  decoration: isWinner
                      ? BoxDecoration(
                          border: Border.all(color: Colors.green, width: 3),
                          borderRadius: BorderRadius.circular(10),
                        )
                      : null,
                  child: _buildCard(pc.card, large: true),
                ),
                const SizedBox(height: 4),
                Text(
                  player.name,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: isWinner ? FontWeight.bold : null,
                    color: isWinner ? Colors.green : null,
                  ),
                ),
              ],
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        if (winner != null)
          Text(
            '${winner.name} wint de slag!',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: Colors.green,
              fontWeight: FontWeight.bold,
            ),
          ),
      ],
    );
  }

  Widget _buildCard(models.Card card, {bool large = false}) {
    final size = large ? 80.0 : 60.0;
    final fontSize = large ? 24.0 : 18.0;

    // Safely get the card text
    String cardText;
    Color cardColor;
    try {
      cardText = '${card.rank.symbol}${card.suit.symbol}';
      cardColor = card.suit.isRed ? Colors.red : Colors.black;
    } catch (e) {
      print('DEBUG _buildCard error: $e, card=$card, rank=${card.rank}, suit=${card.suit}');
      cardText = '?';
      cardColor = Colors.grey;
    }

    return Container(
      width: size * 0.7,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
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

  Widget _buildRoundEndPhase(BuildContext context, GameState game) {
    final theme = Theme.of(context);

    // Sorteer spelers op totaalscore voor weergave
    final sortedPlayers = [...game.players]
      ..sort((a, b) => b.totalScore.compareTo(a.totalScore));

    return Column(
      children: [
        Text(
          'Ronde ${game.currentRoundIndex + 1} klaar!',
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        // Over/onderbod status
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
          child: Text(
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
                final roundScore = game.rules.calculateRoundScore(
                  player.bid!,
                  player.tricksTaken,
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
                  subtitle: Text('Bod: ${player.bid} | Gehaald: ${player.tricksTaken}'),
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

                return ListTile(
                  leading: Text(
                    medal.isNotEmpty ? medal : '${index + 1}.',
                    style: theme.textTheme.headlineMedium,
                  ),
                  title: Text(
                    player.name,
                    style: index == 0 ? const TextStyle(fontWeight: FontWeight.bold) : null,
                  ),
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
