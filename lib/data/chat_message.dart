class ChatMessage {
  final String sender;
  final String message;
  final bool isLocal;
  final DateTime timestamp;

  ChatMessage({
    required this.sender,
    required this.message,
    required this.isLocal,
    required this.timestamp,
  });
}
