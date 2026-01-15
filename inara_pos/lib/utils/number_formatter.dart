import 'package:intl/intl.dart';

class NumberFormatter {
  static final NumberFormat _currency = NumberFormat.currency(
    symbol: 'Rs. ',
    decimalDigits: 2,
    locale: 'en_NP',
  );

  static final NumberFormat _number = NumberFormat.decimalPattern('en_NP');

  static String formatCurrency(double amount) {
    return _currency.format(amount);
  }

  static String formatNumber(double number) {
    return _number.format(number);
  }

  static String formatQuantity(int quantity) {
    return _number.format(quantity);
  }
}
