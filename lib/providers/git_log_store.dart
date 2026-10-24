import 'package:fedit/models/git_models.dart';
import 'package:flutter/foundation.dart';


class GitLogStore extends ChangeNotifier {
  final List<GitOperationEvent> _events = <GitOperationEvent>[];

  List<GitOperationEvent> get events => List.unmodifiable(_events);

  void addAll(Iterable<GitOperationEvent> events) {
    _events.insertAll(0, events);
    if (_events.length > 120) {
      _events.removeRange(120, _events.length);
    }
    notifyListeners();
  }

  void addError(Object error) {
    addAll([GitOperationEvent.error(_sanitizeError(error))]);
  }

  void clear() {
    _events.clear();
    notifyListeners();
  }

  String _sanitizeError(Object error) {
    final message = error.toString().split('\n').first;
    return message.length > 220 ? '${message.substring(0, 220)}...' : message;
  }
}
