import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/formatters.dart';
import '../../domain/models.dart';
import '../controllers/auth_controller.dart';
import '../controllers/jobs_controller.dart';
import '../controllers/payments_controller.dart';

class JobHistoryScreen extends ConsumerWidget {
  const JobHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final user = ref.watch(currentUserProvider);
    final jobsAsync = ref.watch(jobsForCurrentUserProvider);
    final paymentsAsync = ref.watch(paymentsForCurrentUserProvider);
    final payments = paymentsAsync.maybeWhen(
      data: (value) => value,
      orElse: () => const <PaymentRecord>[],
    );
    final paymentsByJobId = <String, PaymentRecord>{};
    for (final payment in payments) {
      final existing = paymentsByJobId[payment.jobId];
      if (existing == null ||
          payment.recordedAt.isAfter(existing.recordedAt)) {
        paymentsByJobId[payment.jobId] = payment;
      }
    }
    return Scaffold(
      appBar: AppBar(title: Text(t.t('job_history'))),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          Text(t.t('jobs'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          jobsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Text(error.toString()),
            data: (jobs) {
              final completedOrCancelled = jobs
                  .where((job) {
                    if (job.assignedProId == null) {
                      return false;
                    }
                    return job.status == JobStatus.completed ||
                        job.status == JobStatus.paidClosed ||
                        job.status == JobStatus.cancelled;
                  })
                  .toList(growable: false)
                ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

              if (completedOrCancelled.isEmpty) {
                return Text(t.t('no_jobs_yet'));
              }
              return Column(
                children: completedOrCancelled
                    .map(
                      (job) => Card(
                        child: ListTile(
                          onTap: () =>
                              context.push('/job/${job.id}', extra: job),
                          title: Text(job.title),
                          subtitle: _JobHistorySubtitle(
                            job: job,
                            payment: paymentsByJobId[job.id],
                            user: user,
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: <Widget>[
                              Text(
                                formatPkr(job.finalAmount ?? job.fixedPrice),
                              ),
                              Text(
                                formatDateTime(job.updatedAt),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
          const SizedBox(height: 10),
          Text(t.t('payments'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          paymentsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Text(error.toString()),
            data: (payments) {
              if (payments.isEmpty) {
                return Text(t.t('no_payment_records'));
              }
              return Column(
                children: payments
                    .map(
                      (payment) => Card(
                        child: ListTile(
                          title: Text(
                            '${t.paymentMethodLabel(payment.method.value)} | ${t.paymentStateLabel(payment.state.value)}',
                          ),
                          subtitle: Text(
                            '${t.t('gross')} ${formatPkr(payment.grossAmount)} | ${t.t('fee')} ${formatPkr(payment.platformFee)} | ${t.t('net')} ${formatPkr(payment.netProAmount)}',
                          ),
                          trailing: Text(formatDateTime(payment.recordedAt)),
                        ),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _JobHistorySubtitle extends StatelessWidget {
  const _JobHistorySubtitle({
    required this.job,
    required this.payment,
    required this.user,
  });

  final Job job;
  final PaymentRecord? payment;
  final AppUser? user;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final isCancelled = job.status == JobStatus.cancelled;
    final statusLabel = isCancelled
        ? t.t('status_cancelled')
        : t.t('status_completed');
    final statusColor =
        isCancelled ? const Color(0xFFB3261E) : const Color(0xFF1B5E20);
    final methodLabel = payment == null
        ? null
        : t.paymentMethodLabel(payment!.method.value);
    final amountLabel =
        user?.role == UserRole.pro ? t.t('earnings') : t.t('price');
    final amount = user?.role == UserRole.pro
        ? (payment?.netProAmount ?? job.finalAmount ?? job.fixedPrice)
        : (payment?.grossAmount ?? job.finalAmount ?? job.fixedPrice);

    final statusLine = isCancelled
        ? statusLabel
        : methodLabel == null
            ? '$statusLabel - $amountLabel ${formatPkr(amount)}'
            : '$statusLabel - Paid by $methodLabel - $amountLabel ${formatPkr(amount)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '${t.categoryLabel(job.category.value)} | ${t.jobStatusLabel(job.status.value)}',
        ),
        const SizedBox(height: 2),
        Text(job.maskedAddress),
        const SizedBox(height: 6),
        Text(
          statusLine,
          style: TextStyle(color: statusColor, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
