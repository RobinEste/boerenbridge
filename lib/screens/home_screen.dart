import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../game/rules.dart';
import '../providers/auth_provider.dart';
import '../providers/lobby_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Initialiseer auth en laad opgeslagen naam
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(authProvider.notifier).initialize();
      final savedName = ref.read(authProvider).displayName;
      if (savedName != null) {
        _nameController.text = savedName;
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _createGame() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showError('Vul je naam in');
      return;
    }

    // Toon instellingen dialog
    final rules = await _showGameSettingsDialog();
    if (rules == null) return; // Gebruiker heeft geannuleerd

    // Sla naam op en log in
    await ref.read(authProvider.notifier).setDisplayName(name);

    // Maak spel aan met gekozen regels
    final joinCode = await ref.read(lobbyProvider.notifier).createGame(name, rules: rules);

    if (joinCode != null && mounted) {
      context.goNamed('lobby', pathParameters: {'joinCode': joinCode}, extra: true);
    }
  }

  Future<GameRules?> _showGameSettingsDialog() async {
    ScoringSystem selectedScoring = ScoringSystem.nederlands;
    int? selectedMaxRounds;

    return showDialog<GameRules>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Spelinstellingen'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Scoring systeem
                  Text(
                    'Puntentelling',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<ScoringSystem>(
                    value: selectedScoring,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: ScoringSystem.values.map((system) {
                      return DropdownMenuItem(
                        value: system,
                        child: Text(system.displayName),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => selectedScoring = value);
                      }
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(
                    selectedScoring.description,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Aantal rondes
                  Text(
                    'Aantal rondes',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int?>(
                    value: selectedMaxRounds,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('Alle rondes (piramide)'),
                      ),
                      const DropdownMenuItem(
                        value: 3,
                        child: Text('3 rondes (snel testen)'),
                      ),
                      const DropdownMenuItem(
                        value: 5,
                        child: Text('5 rondes'),
                      ),
                      const DropdownMenuItem(
                        value: 10,
                        child: Text('10 rondes'),
                      ),
                      const DropdownMenuItem(
                        value: 15,
                        child: Text('15 rondes'),
                      ),
                      const DropdownMenuItem(
                        value: 20,
                        child: Text('20 rondes'),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() => selectedMaxRounds = value);
                    },
                  ),
                  const SizedBox(height: 4),
                  Text(
                    selectedMaxRounds == null
                        ? 'Speel de complete piramide (1→max→1 kaarten)'
                        : 'Speel de eerste $selectedMaxRounds rondes',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Annuleren'),
              ),
              FilledButton(
                onPressed: () {
                  final rules = GameRules(
                    scoringSystem: selectedScoring,
                    maxRounds: selectedMaxRounds,
                  );
                  Navigator.pop(context, rules);
                },
                child: const Text('Spel starten'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _joinGame() async {
    final name = _nameController.text.trim();
    final code = _codeController.text.trim().toUpperCase();

    if (name.isEmpty) {
      _showError('Vul je naam in');
      return;
    }
    if (code.isEmpty || code.length != 4) {
      _showError('Vul een geldige 4-letter code in');
      return;
    }

    // Sla naam op en log in
    await ref.read(authProvider.notifier).setDisplayName(name);

    // Join spel
    final success = await ref.read(lobbyProvider.notifier).joinGame(code, name);

    if (success && mounted) {
      context.goNamed('lobby', pathParameters: {'joinCode': code}, extra: false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authState = ref.watch(authProvider);
    final lobbyState = ref.watch(lobbyProvider);

    final isLoading = authState.isLoading || lobbyState.isLoading;
    final error = authState.error ?? lobbyState.error;

    // Toon errors
    ref.listen<LobbyState>(lobbyProvider, (previous, next) {
      if (next.error != null && next.error != previous?.error) {
        _showError(next.error!);
      }
    });

    return Scaffold(
      backgroundColor: Colors.black,
      body: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Achtergrond afbeelding
            Positioned.fill(
              child: Image.asset(
                'assets/images/home_banner.jpeg',
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
            // Lichte gradient overlay alleen achter de form card
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.15),
                      Colors.black.withValues(alpha: 0.3),
                    ],
                    stops: const [0.0, 0.35, 0.5, 0.7],
                  ),
                ),
              ),
            ),
            // Content
            SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Spacer om content naar beneden te duwen
                      const SizedBox(height: 150),

                      // Form card met beige achtergrond passend bij de illustratie
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5EBD7).withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Naam invoer
                            TextField(
                              controller: _nameController,
                              decoration: const InputDecoration(
                                labelText: 'Jouw naam',
                                prefixIcon: Icon(Icons.person),
                              ),
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.next,
                              enabled: !isLoading,
                            ),
                            const SizedBox(height: 16),

                            // Nieuw spel knop
                            FilledButton.icon(
                              onPressed: isLoading ? null : _createGame,
                              icon: isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.add),
                              label: const Text('Nieuw spel starten'),
                            ),
                            const SizedBox(height: 20),

                            // Divider
                            Row(
                              children: [
                                const Expanded(child: Divider()),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  child: Text(
                                    'of',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                const Expanded(child: Divider()),
                              ],
                            ),
                            const SizedBox(height: 20),

                            // Code invoer
                            TextField(
                              controller: _codeController,
                              decoration: const InputDecoration(
                                labelText: 'Spelcode',
                                prefixIcon: Icon(Icons.tag),
                                hintText: 'ABCD',
                              ),
                              textCapitalization: TextCapitalization.characters,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z]')),
                                LengthLimitingTextInputFormatter(4),
                                UpperCaseTextFormatter(),
                              ],
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _joinGame(),
                              enabled: !isLoading,
                            ),
                            const SizedBox(height: 16),

                            // Join knop
                            OutlinedButton.icon(
                              onPressed: isLoading ? null : _joinGame,
                              icon: const Icon(Icons.login),
                              label: const Text('Deelnemen aan spel'),
                            ),

                            // Error message
                            if (error != null) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
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
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// Formatter om tekst automatisch naar hoofdletters te converteren
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
