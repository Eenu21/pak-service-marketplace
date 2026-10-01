import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/formatters.dart';
import '../../core/services/pro_balance_rules.dart';
import '../../domain/models.dart';
import '../controllers/auth_controller.dart';
import '../controllers/payments_controller.dart';

class ProEarningsScreen extends ConsumerStatefulWidget {
  const ProEarningsScreen({super.key});

  @override
  ConsumerState<ProEarningsScreen> createState() => _ProEarningsScreenState();
}

class _ProEarningsScreenState extends ConsumerState<ProEarningsScreen> {
  bool _payingDue = false;

  Future<void> _payNow(AppUser user, double dueAmount) async {
    final method = await showModalBottomSheet<PaymentMethod>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const ListTile(
                  title: Text(
                    'Select Payment Gateway',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text('Choose how you want to clear app dues.'),
                ),
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: const Text('EasyPaisa'),
                  onTap: () => Navigator.of(context).pop(PaymentMethod.easyPaisa),
                ),
                ListTile(
                  leading: const Icon(Icons.phone_android_outlined),
                  title: const Text('JazzCash'),
                  onTap: () => Navigator.of(context).pop(PaymentMethod.jazzCash),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (method == null) {
      return;
    }

    setState(() => _payingDue = true);
    try {
      await ref.read(paymentsControllerProvider).settleProDue(
            proId: user.id,
            method: method,
            externalReference:
                'due-${method.value}-${DateTime.now().millisecondsSinceEpoch}',
          );
      ref.invalidate(proEarningsProvider);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Payment successful via ${method.displayName}. PKR ${dueAmount.toStringAsFixed(0)} cleared.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) {
        setState(() => _payingDue = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final user = ref.watch(currentUserProvider);
    final earningsAsync = ref.watch(proEarningsProvider);
    final paymentsAsync = ref.watch(paymentsForCurrentUserProvider);
    final financial = ref.watch(proFinancialStatusProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t.t('earnings_dashboard'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: <Widget>[
            if (financial != null && financial.level != ProDueLevel.clear)
              _DueBanner(level: financial.level),
            earningsAsync.when(
              loading: () => const LinearProgressIndicator(),
              error: (error, _) => Text(error.toString()),
              data: (summary) {
                if (summary == null) {
                  return const SizedBox.shrink();
                }
                return Column(
                  children: <Widget>[
                    _StatCard(
                      title: 'Total Earnings',
                      value: formatPkr(summary.totalEarnings),
                    ),
                    _StatCard(
                      title: 'Due to App',
                      value: formatPkr(summary.dueToApp),
                    ),
                    if (user != null && summary.dueToApp > 0)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _payingDue
                                ? null
                                : () => _payNow(user, summary.dueToApp),
                            child: _payingDue
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text('${t.t('pay_now')} (EasyPaisa / JazzCash)'),
                          ),
                        ),
                      ),
                    _StatCard(
                      title: t.t('today'),
                      value: formatPkr(summary.today),
                    ),
                    _StatCard(
                      title: t.t('this_month'),
                      value: formatPkr(summary.month),
                    ),
                    _StatCard(
                      title: t.t('lifetime'),
                      value: formatPkr(summary.lifetime),
                    ),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _StatCard(
                            title: t.t('online'),
                            value: formatPkr(summary.online),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatCard(
                            title: t.t('cash'),
                            value: formatPkr(summary.cash),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _StatCard(
                            title: t.t('platform_fees'),
                            value: formatPkr(summary.platformFees),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _StatCard(
                            title: t.t('completed_jobs'),
                            value: '${summary.totalJobs}',
                          ),
                        ),
                      ],
                    ),
                    _StatCard(
                      title: t.t('rating'),
                      value:
                          '${summary.averageRating.toStringAsFixed(1)} (${summary.totalReviews})',
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                t.t('payment_records'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const SizedBox(height: 8),
            paymentsAsync.when(
              loading: () => const CircularProgressIndicator(),
              error: (error, _) => Text(error.toString()),
              data: (payments) {
                if (payments.isEmpty) {
                  return Text(t.t('no_payment_records'));
                }
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemBuilder: (_, index) {
                    final payment = payments[index];
                    return Card(
                      child: ListTile(
                        title: Text(
                          '${t.paymentMethodLabel(payment.method.value)} | ${t.paymentStateLabel(payment.state.value)}',
                        ),
                        subtitle: Text(
                          '${t.t('gross')} ${formatPkr(payment.grossAmount)} | ${t.t('fee')} ${formatPkr(payment.platformFee)} | ${t.t('net')} ${formatPkr(payment.netProAmount)}',
                        ),
                        trailing: Text(
                          formatDateTime(payment.recordedAt),
                          textAlign: TextAlign.end,
                        ),
                      ),
                    );
                  },
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemCount: payments.length,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DueBanner extends StatelessWidget {
  const _DueBanner({required this.level});

  final ProDueLevel level;

  @override
  Widget build(BuildContext context) {
    final message = switch (level) {
      ProDueLevel.mild =>
        "You're 75% of the way to your limit. Pay soon to keep working!",
      ProDueLevel.strong =>
        'Urgent: Pay your dues now or your account will be locked soon.',
      ProDueLevel.locked =>
        'Account Locked. Please clear your 2,000 PKR due to continue bidding on jobs.',
      ProDueLevel.clear => '',
    };
    final color = switch (level) {
      ProDueLevel.mild => const Color(0xFFFFF7E0),
      ProDueLevel.strong => const Color(0xFFFFEAD6),
      ProDueLevel.locked => const Color(0xFFFFE0E0),
      ProDueLevel.clear => Colors.transparent,
    };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Text(
        message,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(title),
        trailing: Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}
