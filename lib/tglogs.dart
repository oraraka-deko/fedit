import 'dart:convert';
import 'package:http/http.dart' as http;
import 'env.dart';
/// Sends a log message to a specified Telegram chat via the Bot API.
///
/// Features graceful failure handling: network dropouts, HTTP errors,
/// long message chunking, and Telegram HTML entity escaping.
Future<bool> sendTelegramLog(
  String logMessage, {
  String chatId = '8128288493',
  Duration timeout = const Duration(seconds: 10),
}) async {
  if (logMessage.trim().isEmpty) return false;

  // Telegram enforces a maximum of 4096 characters per message
  const int maxChunkSize = 3900;
  final chunks = _splitMessage(logMessage, maxChunkSize);

  bool allSucceeded = true;

  for (final chunk in chunks) {
    final sanitizedLog = _escapeHtml(chunk);
    final formattedMessage = '<b>[Log]</b>\n<pre>$sanitizedLog</pre>';

    final uri = Uri.parse('https://api.telegram.org/bot$botToken/sendMessage');

    try {
      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'chat_id': chatId,
              'text': formattedMessage,
              'parse_mode': 'HTML',
              'disable_web_page_preview': true,
            }),
          )
          .timeout(timeout);

      if (response.statusCode != 200) {
        // HTTP errors (e.g., rate-limiting 429, invalid token 401, blocked bot)
        print('Telegram log failed with status: ${response.statusCode} - ${response.body}');
        allSucceeded = false;
      }
    } catch (e) {
      // Gracefully catches SocketException (no network), TimeoutException, ClientException
      print('Telegram log delivery error (swallowed to prevent crash): $e');
      allSucceeded = false;
    }
  }

  return allSucceeded;
}

/// Escapes HTML characters so stack traces and symbols don't break Telegram parsing.
String _escapeHtml(String text) {
  return text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
}

/// Splits long messages to respect Telegram's message limits.
List<String> _splitMessage(String text, int chunkSize) {
  final List<String> chunks = [];
  int offset = 0;

  while (offset < text.length) {
    int end = offset + chunkSize;
    if (end > text.length) end = text.length;
    chunks.add(text.substring(offset, end));
    offset = end;
  }

  return chunks;
}