import 'package:flutter/material.dart';

import 'editor_session_manager.dart';

class SessionScope extends InheritedNotifier<EditorSessionManager> {
  const SessionScope({
    super.key,
    required EditorSessionManager session,
    required super.child,
  }) : super(notifier: session);

  static EditorSessionManager of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SessionScope>();
    assert(scope != null, 'No SessionScope found in context');
    return scope!.notifier!;
  }
}
