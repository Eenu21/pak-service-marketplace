import '../../domain/models.dart';

DateTime? workStartedAt(Job job) {
  for (final event in job.timeline.reversed) {
    if (event.type == 'work_started') {
      return event.at;
    }
  }
  return null;
}

DateTime? workStoppedAt(Job job) {
  const stopTypes = <String>{
    'completed',
    'paid_closed',
    'cancelled',
  };
  for (final event in job.timeline.reversed) {
    if (stopTypes.contains(event.type)) {
      return event.at;
    }
  }
  return null;
}

Duration? workElapsed(Job job, {DateTime? now}) {
  final started = workStartedAt(job);
  if (started == null) {
    return null;
  }
  final end = workStoppedAt(job) ?? (now ?? DateTime.now());
  final diff = end.difference(started);
  return diff.isNegative ? Duration.zero : diff;
}

bool hasPendingCompletionRequest(Job job) {
  const resolvedTypes = <String>{
    'completion_rejected',
    'completed',
    'paid_closed',
    'cancelled',
    'disputed',
  };
  for (final event in job.timeline.reversed) {
    if (event.type == 'completion_requested') {
      return true;
    }
    if (resolvedTypes.contains(event.type)) {
      return false;
    }
  }
  return false;
}

String formatWorkDuration(Duration duration) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) {
    return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
  }
  return '${twoDigits(minutes)}:${twoDigits(seconds)}';
}
