/// Chat bericht model voor in-game chat
class ChatMessage {
  final String id;
  final String gameId;
  final String playerId;
  final String playerName;
  final String content;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.gameId,
    required this.playerId,
    required this.playerName,
    required this.content,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'game_id': gameId,
        'player_id': playerId,
        'content': content,
        'created_at': createdAt.toIso8601String(),
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    // Player name komt uit joined data
    final playerData = json['game_players'] as Map<String, dynamic>?;
    final playerName = playerData?['display_name'] as String? ?? 'Onbekend';

    return ChatMessage(
      id: json['id'].toString(),
      gameId: json['game_id'] as String,
      playerId: json['player_id'] as String,
      playerName: playerName,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ChatMessage && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
