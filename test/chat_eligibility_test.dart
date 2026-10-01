import 'package:flutter_test/flutter_test.dart';
import 'package:pak_service_marketplace/src/domain/models.dart';

void main() {
  test('chat is only enabled after a professional is assigned', () {
    expect(JobStatus.posted.allowsChat, isFalse);
    expect(JobStatus.available.allowsChat, isFalse);
    expect(JobStatus.inProcess.allowsChat, isTrue);
    expect(JobStatus.completed.allowsChat, isTrue);
    expect(JobStatus.paidClosed.allowsChat, isTrue);
    expect(JobStatus.cancelled.allowsChat, isFalse);
    expect(JobStatus.disputed.allowsChat, isTrue);
  });
}
