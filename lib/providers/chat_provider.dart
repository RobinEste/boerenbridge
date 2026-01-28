import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../game/chat_message.dart';
import '../services/supabase_service.dart';

/// Chat state
class ChatState {
  final List<ChatMessage> messages;
  final bool isLoading;
  final String? error;
  final int unreadCount;

  const ChatState({
    this.messages = const [],
    this.isLoading = false,
    this.error,
    this.unreadCount = 0,
  });

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
    String? error,
    int? unreadCount,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}

/// Chat provider - beheert chat state voor een game
class ChatNotifier extends StateNotifier<ChatState> {
  ChatNotifier() : super(const ChatState());

  StreamSubscription<ChatMessage>? _chatSubscription;
  String? _currentGameId;
  String? _currentPlayerId;
  bool _isChatOpen = false;

  /// Initialiseer chat voor een game
  Future<void> initialize(String gameId, String playerId) async {
    if (_currentGameId == gameId) return;

    _currentGameId = gameId;
    _currentPlayerId = playerId;
    state = state.copyWith(isLoading: true, error: null);

    try {
      // Laad bestaande berichten
      final messages = await SupabaseService.instance.getChatMessages(gameId);

      // Subscribe op nieuwe berichten
      SupabaseService.instance.subscribeToChat(gameId);
      _chatSubscription?.cancel();
      _chatSubscription = SupabaseService.instance.chatMessageStream.listen(
        (message) {
          // Voeg nieuw bericht toe
          final updatedMessages = [...state.messages, message];
          final newUnread = _isChatOpen ? 0 : state.unreadCount + 1;
          state = state.copyWith(
            messages: updatedMessages,
            unreadCount: newUnread,
          );
        },
        onError: (e) {
          state = state.copyWith(error: 'Chat verbinding verloren');
        },
      );

      state = state.copyWith(
        messages: messages,
        isLoading: false,
        unreadCount: 0,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Kon chat niet laden: $e',
      );
    }
  }

  /// Stuur een bericht
  Future<void> sendMessage(String content) async {
    if (_currentGameId == null || _currentPlayerId == null) return;
    if (content.trim().isEmpty) return;

    try {
      await SupabaseService.instance.sendChatMessage(
        _currentGameId!,
        _currentPlayerId!,
        content,
      );
    } catch (e) {
      state = state.copyWith(error: 'Kon bericht niet versturen');
    }
  }

  /// Markeer chat als geopend (reset unread count)
  void markChatOpened() {
    _isChatOpen = true;
    state = state.copyWith(unreadCount: 0);
  }

  /// Markeer chat als gesloten
  void markChatClosed() {
    _isChatOpen = false;
  }

  /// Clear error
  void clearError() {
    state = state.copyWith(error: null);
  }

  /// Cleanup
  void cleanup() {
    _chatSubscription?.cancel();
    SupabaseService.instance.unsubscribeFromChat();
    _currentGameId = null;
    _currentPlayerId = null;
    state = const ChatState();
  }

  @override
  void dispose() {
    _chatSubscription?.cancel();
    super.dispose();
  }
}

/// Global chat provider
final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  return ChatNotifier();
});
