import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config.dart' show AppConfig;
import '../providers/lobby_provider.dart';

class LobbyScreen extends ConsumerStatefulWidget {
  final String joinCode;
  final bool isHost;

  const LobbyScreen({
    super.key,
    required this.joinCode,
    required this.isHost,
  });

  @override
  ConsumerState<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends ConsumerState<LobbyScreen> {
  @override
  void initState() {
    super.initState();
    // Luister naar game started event
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.listenManual(lobbyProvider, (previous, next) {
        if (next.gameStarted && next.gameId != null) {
          context.goNamed('game', pathParameters: {'gameId': next.gameId!});
        }
      });
    });
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: widget.joinCode));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Code gekopieerd!'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _leaveLobby() {
    ref.read(lobbyProvider.notifier).leaveLobby();
    context.go('/');
  }

  Future<void> _startGame() async {
    final success = await ref.read(lobbyProvider.notifier).startGame();
    if (success) {
      final gameId = ref.read(lobbyProvider).gameId;
      if (gameId != null && mounted) {
        context.goNamed('game', pathParameters: {'gameId': gameId});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lobbyState = ref.watch(lobbyProvider);

    final players = lobbyState.players;
    final isLoading = lobbyState.isLoading;
    final error = lobbyState.error;

    // Debug info
    print('LOBBY BUILD: gameId=${lobbyState.gameId}, players=${players.length}, isHost=${lobbyState.isHost}');
    for (final p in players) {
      print('LOBBY PLAYER: ${p.name} (${p.id})');
    }

    // Toon errors
    ref.listen<LobbyState>(lobbyProvider, (previous, next) {
      if (next.error != null && next.error != previous?.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.error!),
            backgroundColor: theme.colorScheme.error,
          ),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _leaveLobby,
        ),
        title: const Text('Wachtkamer'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Join code card
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Text(
                        'Deel deze code:',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 16),
                      InkWell(
                        onTap: _copyCode,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 32,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                widget.joinCode,
                                style: theme.textTheme.headlineLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 8,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Icon(
                                Icons.copy,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tik om te kopieren',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // DEBUG: Show state info
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.yellow.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'DEBUG: gameId=${lobbyState.gameId?.substring(0, 8) ?? "null"}, '
                  'players=${players.length}, isHost=${lobbyState.isHost}',
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ),

              // Spelers lijst
              Text(
                'Spelers (${players.length}/${AppConfig.maxPlayers})',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Card(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: AppConfig.maxPlayers,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      if (index < players.length) {
                        final player = players[index];
                        final isHostPlayer = index == 0;

                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: theme.colorScheme.primary,
                            child: Text(
                              player.name[0].toUpperCase(),
                              style: TextStyle(
                                color: theme.colorScheme.onPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(player.name),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isHostPlayer)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    'Host',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.onSecondaryContainer,
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.check_circle,
                                color: theme.colorScheme.primary,
                              ),
                            ],
                          ),
                        );
                      } else {
                        // Empty slot
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: theme.colorScheme.surfaceContainerHighest,
                            child: Icon(
                              Icons.person_outline,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          title: Text(
                            'Wachten op speler...',
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Error message
              if (error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          error,
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Start knop (alleen voor host)
              if (widget.isHost)
                FilledButton.icon(
                  onPressed: isLoading || players.length < AppConfig.minPlayers
                      ? null
                      : _startGame,
                  icon: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(
                    players.length < AppConfig.minPlayers
                        ? 'Wacht op meer spelers...'
                        : 'Start spel',
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Wachten tot host het spel start...',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
