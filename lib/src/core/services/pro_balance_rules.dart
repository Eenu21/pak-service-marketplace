enum ProDueLevel { clear, mild, strong, locked }

class ProBalanceRules {
  const ProBalanceRules._();

  static const double commissionRate = 0.10;
  static const double dueLimit = 2000;
  static const double mildWarning = 1500;
  static const double strongWarning = 1800;

  static bool isLocked(double due) => due >= dueLimit;

  static ProDueLevel levelFor(double due) {
    if (due >= dueLimit) {
      return ProDueLevel.locked;
    }
    if (due >= strongWarning) {
      return ProDueLevel.strong;
    }
    if (due >= mildWarning) {
      return ProDueLevel.mild;
    }
    return ProDueLevel.clear;
  }
}
