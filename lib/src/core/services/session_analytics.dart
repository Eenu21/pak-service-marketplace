import '../../domain/models.dart';

class UserSessionRecord {
  const UserSessionRecord({
    required this.userId,
    required this.startedAt,
    required this.endedAt,
  });

  final String userId;
  final DateTime startedAt;
  final DateTime endedAt;

  Duration get duration => endedAt.difference(startedAt);
}

class SessionAnalytics {
  const SessionAnalytics._();

  static List<UserSessionRecord> completedSessions(
    Iterable<AuditEvent> auditEvents,
  ) {
    final events = auditEvents.toList(growable: false)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final openSessions = <String, UserSessionRecord>{};
    final legacySessionsByUser = <String, List<String>>{};
    final completed = <UserSessionRecord>[];

    for (final event in events) {
      if (event.entityType != 'session') {
        continue;
      }

      if (event.action == 'login' || event.action == 'session_resumed') {
        final sessionId = event.metadata['session_id'];
        final key = sessionId is String && sessionId.isNotEmpty
            ? '${event.actorId}:$sessionId'
            : '${event.actorId}:legacy:${event.id}';
        openSessions.putIfAbsent(
          key,
          () => UserSessionRecord(
            userId: event.actorId,
            startedAt: event.createdAt,
            endedAt: event.createdAt,
          ),
        );
        if (sessionId is! String || sessionId.isEmpty) {
          legacySessionsByUser
              .putIfAbsent(event.actorId, () => <String>[])
              .add(key);
        }
        continue;
      }

      if (event.action != 'logout') {
        continue;
      }

      final sessionId = event.metadata['session_id'];
      String? key;
      if (sessionId is String && sessionId.isNotEmpty) {
        key = '${event.actorId}:$sessionId';
      } else {
        final legacy = legacySessionsByUser[event.actorId];
        if (legacy != null && legacy.isNotEmpty) {
          key = legacy.removeAt(0);
        }
      }
      if (key == null) {
        continue;
      }

      final opened = openSessions.remove(key);
      if (opened == null || event.createdAt.isBefore(opened.startedAt)) {
        continue;
      }
      completed.add(
        UserSessionRecord(
          userId: opened.userId,
          startedAt: opened.startedAt,
          endedAt: event.createdAt,
        ),
      );
    }

    return List<UserSessionRecord>.unmodifiable(completed);
  }
}
