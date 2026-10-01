import '../../data/repositories/marketplace_repository.dart';

class PaymentCalculator {
  const PaymentCalculator(this.commissionRate);

  final double commissionRate;

  PaymentCalculation calculate(double amount) {
    final fee = double.parse((amount * commissionRate).toStringAsFixed(2));
    final net = double.parse((amount - fee).toStringAsFixed(2));
    return PaymentCalculation(gross: amount, fee: fee, net: net);
  }
}
