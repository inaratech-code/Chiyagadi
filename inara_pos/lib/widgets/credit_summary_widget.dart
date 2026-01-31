import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/database_provider.dart';
import '../screens/customers/customers_screen.dart';
import 'package:intl/intl.dart';

class CreditSummaryWidget extends StatefulWidget {
  const CreditSummaryWidget({super.key});

  @override
  State<CreditSummaryWidget> createState() => _CreditSummaryWidgetState();
}

class _CreditSummaryWidgetState extends State<CreditSummaryWidget> {
  double _totalCredits = 0.0;
  int _customersWithCredit = 0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadCreditSummary();
  }

  Future<void> _loadCreditSummary() async {
    try {
      final dbProvider = Provider.of<DatabaseProvider>(context, listen: false);
      await dbProvider.init();

      final customers = await dbProvider.query('customers');
      _totalCredits = customers.fold(
          0.0, (sum, c) => sum + (c['credit_balance'] as num? ?? 0).toDouble());
      _customersWithCredit =
          customers.where((c) => (c['credit_balance'] as num? ?? 0) > 0).length;
    } catch (e) {
      debugPrint('Error loading credit summary: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Card(
        color: Colors.orange[50],
        child: const Padding(
          padding: EdgeInsets.all(16.0),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Card(
      color: _totalCredits > 0 ? Colors.orange[50] : Colors.green[50],
      elevation: 2,
      child: InkWell(
        onTap: () {
          // Navigate to customers screen
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CustomersScreen()),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.account_balance_wallet,
                    color: _totalCredits > 0
                        ? Colors.orange[900]
                        : Colors.green[700],
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Credit Summary',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _totalCredits > 0
                              ? Colors.orange[900]
                              : Colors.green[700],
                        ),
                  ),
                  const Spacer(),
                  if (_totalCredits > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange[200],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_customersWithCredit} Customer${_customersWithCredit != 1 ? 's' : ''}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[900],
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Outstanding',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        NumberFormat.currency(symbol: 'NPR ')
                            .format(_totalCredits),
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _totalCredits > 0
                              ? Colors.orange[900]
                              : Colors.green[700],
                        ),
                      ),
                    ],
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.grey[600],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
