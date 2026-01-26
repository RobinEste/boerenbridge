import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'supabase_service.dart';

/// Connection state voor de applicatie
enum AppConnectionState {
  connected,
  connecting,
  disconnected,
  reconnecting,
}

/// Service voor het beheren van de verbindingsstatus en automatisch herverbinden
class ConnectionService {
  final String gameId;
  final VoidCallback? onReconnected;
  final VoidCallback? onGaveUp;

  AppConnectionState _state = AppConnectionState.connected;
  AppConnectionState get state => _state;

  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;

  static const int _heartbeatIntervalSeconds = 10;
  static const int _maxReconnectAttempts = 10;
  static const int _maxReconnectDelaySeconds = 30;

  final _stateController = StreamController<AppConnectionState>.broadcast();
  Stream<AppConnectionState> get stateStream => _stateController.stream;

  ConnectionService({
    required this.gameId,
    this.onReconnected,
    this.onGaveUp,
  });

  /// Start de heartbeat en connection monitoring
  void start() {
    _state = AppConnectionState.connected;
    _stateController.add(_state);
    _startHeartbeat();
  }

  /// Stop de service
  void stop() {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectTimer = null;
    _stateController.close();
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: _heartbeatIntervalSeconds),
      (_) => _sendHeartbeat(),
    );
    // Direct eerste heartbeat sturen
    _sendHeartbeat();
  }

  Future<void> _sendHeartbeat() async {
    try {
      await SupabaseService.instance.updateLastSeen(gameId);

      // Verbinding is weer goed
      if (_state != AppConnectionState.connected) {
        _state = AppConnectionState.connected;
        _stateController.add(_state);
        _reconnectAttempts = 0;
        onReconnected?.call();
      }
    } catch (e) {
      // Heartbeat gefaald - start reconnect
      if (_state == AppConnectionState.connected) {
        _handleDisconnect();
      }
    }
  }

  void _handleDisconnect() {
    _state = AppConnectionState.disconnected;
    _stateController.add(_state);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      _state = AppConnectionState.disconnected;
      _stateController.add(_state);
      onGaveUp?.call();
      return;
    }

    // Exponential backoff: 1s, 2s, 4s, 8s, 16s, max 30s
    final delaySeconds = min(
      pow(2, _reconnectAttempts).toInt(),
      _maxReconnectDelaySeconds,
    );
    _reconnectAttempts++;

    _state = AppConnectionState.reconnecting;
    _stateController.add(_state);

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      Duration(seconds: delaySeconds),
      _attemptReconnect,
    );
  }

  Future<void> _attemptReconnect() async {
    try {
      // Probeer game state op te halen als test
      final gameState = await SupabaseService.instance.getGameState(gameId);
      if (gameState != null) {
        // Re-subscribe op realtime updates
        SupabaseService.instance.subscribeToGame(gameId);

        // Stuur heartbeat
        await SupabaseService.instance.updateLastSeen(gameId);

        _state = AppConnectionState.connected;
        _stateController.add(_state);
        _reconnectAttempts = 0;
        onReconnected?.call();
        return;
      }
    } catch (e) {
      // Reconnect gefaald
    }

    // Probeer opnieuw
    _scheduleReconnect();
  }

  /// Forceer een reconnect poging
  void forceReconnect() {
    _reconnectAttempts = 0;
    _attemptReconnect();
  }

  /// Annuleer reconnect pogingen
  void cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _state = AppConnectionState.disconnected;
    _stateController.add(_state);
  }

  int get reconnectAttempt => _reconnectAttempts;
}
