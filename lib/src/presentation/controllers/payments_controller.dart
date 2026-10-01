import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/repository_provider.dart';
import '../../core/services/pro_balance_rules.dart';
import '../../data/repositories/marketplace_repository.dart';
import '../../domain/models.dart';
import 'auth_controller.dart';

final paymentsForCurrentUserProvider = StreamProvider<List<PaymentRecord>>((ref) {
  final repository = ref.watch(marketplaceRepositoryProvider);
  final user = ref.watch(currentUserProvider);
  if (user == null) {
    return const Stream<List<PaymentRecord>>.empty();
  }
  if (user.role == UserRole.pro) {
    return repository.watchPaymentsForPro(user.id);
  }
  return repository.watchPaymentsForUser(user.id);
});

final proEarningsProvider = FutureProvider<ProEarningsSummary?>((ref) async {
  final repository = ref.watch(marketplaceRepositoryProvider);
  final user = ref.watch(currentUserProvider);
  if (user == null || user.role != UserRole.pro) {
    return null;
  }
  return repository.fetchEarningsSummary(user.id);
});

class ProFinancialStatus {
  const ProFinancialStatus({
    required this.totalEarnings,
    required this.dueToApp,
    required this.level,
  });

  final double totalEarnings;
  final double dueToApp;
  final ProDueLevel level;

  bool get isLocked => level == ProDueLevel.locked;
  bool get showMildWarning => level == ProDueLevel.mild;
  bool get showStrongWarning => level == ProDueLevel.strong;
}

final proFinancialStatusProvider = Provider<ProFinancialStatus?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null || user.role != UserRole.pro) {
    return null;
  }
  return ProFinancialStatus(
    totalEarnings: user.totalEarnings,
    dueToApp: user.dueToApp,
    level: ProBalanceRules.levelFor(user.dueToApp),
  );
});

class PaymentsController {
  PaymentsController(this._repository);

  final MarketplaceRepository _repository;

  PaymentCalculation calculate(double amount, {JobCategory? category}) {
    if (category == null) {
      return _repository.calculatePayment(amount);
    }
    return _repository.calculatePaymentForCategory(
      amount: amount,
      category: category,
    );
  }

  Future<PaymentRecord> record(PaymentRequest request) => _repository.recordPayment(request);

  Future<void> settleProDue({
    required String proId,
    required PaymentMethod method,
    String? externalReference,
  }) {
    return _repository.settleProDue(
      proId: proId,
      method: method,
      externalReference: externalReference,
    );
  }
}

final paymentsControllerProvider = Provider<PaymentsController>((ref) {
  return PaymentsController(ref.watch(marketplaceRepositoryProvider));
});
