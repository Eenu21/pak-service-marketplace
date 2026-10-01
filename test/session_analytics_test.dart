import 'package:flutter_test/flutter_test.dart';
import 'package:pak_service_marketplace/src/core/services/session_analytics.dart';
import 'package:pak_service_marketplace/src/domain/models.dart';

void main() {
  AuditEvent event({
    required String id,
    required String userId,
    required String action,
    required DateTime at,
    String? sessionId,
    String entityType = 'session',
  }) {
    return AuditEvent(
      id: id,
      actorId: userId,
      action: action,
      entityType: entityType,
      entityId: userId,
      createdAt: at,
      metadata: <String, dynamic>{'session_id': sessionId},
    );
  }

  test('pairs login and logout per user session', () {
    final start = DateTime(2026, 10, 1, 9);
    final records = SessionAnalytics.completedSessions(<AuditEvent>[
      event(
        id: 'login',
        userId: 'user-1',
        action: 'login',
        at: start,
        sessionId: 'session-1',
      ),
      event(
        id: 'unrelated',
        userId: 'user-1',
        action: 'job_status_updated',
        at: start.add(const Duration(minutes: 20)),
        sessionId: 'session-1',
        entityType: 'job',
      ),
      event(
        id: 'logout',
        userId: 'user-1',
        action: 'logout',
        at: start.add(const Duration(hours: 2)),
        sessionId: 'session-1',
      ),
    ]);

    expect(records, hasLength(1));
    expect(records.single.userId, 'user-1');
    expect(records.single.duration, const Duration(hours: 2));
  });

  test('supports older session events without session IDs', () {
    final start = DateTime(2026, 10, 1, 9);
    final records = SessionAnalytics.completedSessions(<AuditEvent>[
      event(id: 'login', userId: 'user-1', action: 'login', at: start),
      event(
        id: 'logout',
        userId: 'user-1',
        action: 'logout',
        at: start.add(const Duration(minutes: 30)),
      ),
    ]);

    expect(records, hasLength(1));
    expect(records.single.duration, const Duration(minutes: 30));
  });

  test('keeps one session open across app resume events', () {
    final start = DateTime(2026, 10, 1, 9);
    final records = SessionAnalytics.completedSessions(<AuditEvent>[
      event(
        id: 'login',
        userId: 'user-1',
        action: 'login',
        at: start,
        sessionId: 'session-1',
      ),
      event(
        id: 'resume',
        userId: 'user-1',
        action: 'session_resumed',
        at: start.add(const Duration(minutes: 25)),
        sessionId: 'session-1',
      ),
      event(
        id: 'logout',
        userId: 'user-1',
        action: 'logout',
        at: start.add(const Duration(hours: 1)),
        sessionId: 'session-1',
      ),
    ]);

    expect(records, hasLength(1));
    expect(records.single.startedAt, start);
    expect(records.single.duration, const Duration(hours: 1));
  });

  test('does not invent a duration for sessions without a logout', () {
    final records = SessionAnalytics.completedSessions(<AuditEvent>[
      event(
        id: 'login',
        userId: 'user-1',
        action: 'login',
        at: DateTime(2026, 10, 1),
        sessionId: 'session-1',
      ),
    ]);

    expect(records, isEmpty);
  });
}
