import 'package:intl/intl.dart';

final _currency = NumberFormat.currency(locale: 'en_PK', symbol: 'PKR ', decimalDigits: 0);

String formatPkr(num value) => _currency.format(value);

String formatDateTime(DateTime value) => DateFormat('dd MMM yyyy, hh:mm a').format(value);
