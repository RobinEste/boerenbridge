import 'package:flutter/material.dart';

import '../services/connection_service.dart';
import '../theme/app_colors.dart';

/// Overlay widget die verbindingsproblemen toont en reconnect opties biedt
class ConnectionOverlay extends StatelessWidget {
  final ConnectionService connectionService;
  final Stream<AppConnectionState> stateStream;
  final VoidCallback onCancel;
  final Widget child;

  const ConnectionOverlay({
    super.key,
    required this.connectionService,
    required this.stateStream,
    required this.onCancel,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppConnectionState>(
      stream: stateStream,
      initialData: AppConnectionState.connected,
      builder: (context, snapshot) {
        final state = snapshot.data ?? AppConnectionState.connected;

        if (state == AppConnectionState.connected) {
          return child;
        }

        return Stack(
          children: [
            child,
            _buildOverlay(context, state),
          ],
        );
      },
    );
  }

  Widget _buildOverlay(BuildContext context, AppConnectionState state) {
    final theme = Theme.of(context);
    final isReconnecting = state == AppConnectionState.reconnecting;

    return Container(
      color: AppColors.warmBrown.withValues(alpha: 0.85),
      child: Center(
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isReconnecting ? Icons.wifi_off : Icons.cloud_off,
                  size: 64,
                  color: isReconnecting ? Colors.orange : theme.colorScheme.error,
                ),
                const SizedBox(height: 24),
                Text(
                  'Verbinding verloren',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                if (isReconnecting) ...[
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Opnieuw verbinden... (poging ${connectionService.reconnectAttempt})',
                        style: theme.textTheme.bodyLarge,
                      ),
                    ],
                  ),
                ] else ...[
                  Text(
                    'Kon geen verbinding maken met de server',
                    style: theme.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 32),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onCancel,
                      icon: const Icon(Icons.home),
                      label: const Text('Terug naar home'),
                    ),
                    const SizedBox(width: 16),
                    if (!isReconnecting)
                      FilledButton.icon(
                        onPressed: () => connectionService.forceReconnect(),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Opnieuw proberen'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
