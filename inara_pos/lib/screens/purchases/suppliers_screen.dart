import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import '../../providers/unified_database_provider.dart';
import '../../providers/auth_provider.dart' show InaraAuthProvider;
import '../../models/supplier_model.dart';
import '../../services/supplier_service.dart';
import '../../utils/theme.dart';
import 'package:intl/intl.dart';
import '../purchases/purchases_screen.dart';

class SuppliersScreen extends StatefulWidget {
  final bool hideAppBar;
  const SuppliersScreen({super.key, this.hideAppBar = false});

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  final SupplierService _supplierService = SupplierService();
  List<Supplier> _suppliers = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    // PERF: Let the screen render first.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSuppliers());
  }

  Future<void> _loadSuppliers() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final suppliers = await _supplierService.getAllSuppliers(
        context: context,
        // Always show all suppliers (active + inactive). Do not hide anything.
        activeOnly: false,
      );
      if (mounted) {
        setState(() {
          _suppliers = suppliers;
        });
      }
    } catch (e) {
      debugPrint('Error loading suppliers: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading suppliers: $e'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<Supplier> get _filteredSuppliers {
    if (_searchQuery.isEmpty) {
      return _suppliers;
    }
    return _suppliers
        .where((s) =>
            s.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            (s.contactPerson != null &&
                s.contactPerson!
                    .toLowerCase()
                    .contains(_searchQuery.toLowerCase())) ||
            (s.phone != null && s.phone!.contains(_searchQuery)) ||
            (s.email != null &&
                s.email!.toLowerCase().contains(_searchQuery.toLowerCase())))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.hideAppBar
          ? null
          : AppBar(
              title: const Text('Suppliers / Parties'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadSuppliers,
                  tooltip: 'Refresh',
                ),
              ],
            ),
      body: Column(
        children: [
          // Search Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search suppliers...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.logoPrimary, width: 2),
                ),
                filled: true,
                fillColor: Colors.grey[50],
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value;
                });
              },
            ),
          ),

          // Suppliers List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredSuppliers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.business,
                                size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'No suppliers found'
                                  : 'No suppliers match your search',
                              style: TextStyle(
                                  color: Colors.grey[600], fontSize: 16),
                            ),
                            if (_searchQuery.isEmpty) ...[
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                onPressed: () => _showAddSupplierDialog(),
                                icon: const Icon(Icons.add),
                                label: const Text('Add Supplier'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppTheme.logoPrimary,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredSuppliers.length,
                        itemBuilder: (context, index) {
                          final supplier = _filteredSuppliers[index];
                          return _buildSupplierCard(supplier);
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: _filteredSuppliers.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => _showAddSupplierDialog(),
              backgroundColor: AppTheme.logoPrimary,
              icon: const Icon(Icons.add),
              label: const Text('Add Supplier'),
            )
          : null,
    );
  }

  Widget _buildSupplierCard(Supplier supplier) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: supplier.isActive ? AppTheme.successColor : Colors.grey[300]!,
          width: 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor:
              supplier.isActive ? AppTheme.logoPrimary : Colors.grey,
          radius: 24,
          child: Text(
            supplier.name.substring(0, 1).toUpperCase(),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                supplier.name,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  decoration:
                      supplier.isActive ? null : TextDecoration.lineThrough,
                ),
              ),
            ),
            if (!supplier.isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Inactive',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (supplier.contactPerson != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.person, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    supplier.contactPerson!,
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  ),
                ],
              ),
            ],
            if (supplier.phone != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.phone, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    supplier.phone!,
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  ),
                ],
              ),
            ],
            if (supplier.email != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.email, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      supplier.email!,
                      style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
            if (supplier.address != null) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.location_on, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      supplier.address!,
                      style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        trailing: PopupMenuButton(
          icon: const Icon(Icons.more_vert),
          itemBuilder: (context) => [
            PopupMenuItem(
              child: const Row(
                children: [
                  Icon(Icons.edit, size: 18),
                  SizedBox(width: 8),
                  Text('Edit'),
                ],
              ),
              onTap: () {
                Future.delayed(const Duration(milliseconds: 100), () {
                  _showEditSupplierDialog(supplier);
                });
              },
            ),
            PopupMenuItem(
              child: Row(
                children: [
                  Icon(
                    supplier.isActive ? Icons.block : Icons.check_circle,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(supplier.isActive ? 'Deactivate' : 'Activate'),
                ],
              ),
              onTap: () {
                Future.delayed(const Duration(milliseconds: 100), () {
                  _toggleSupplierStatus(supplier);
                });
              },
            ),
          ],
        ),
        onTap: () => _showSupplierDetails(supplier),
      ),
    );
  }

  Future<void> _showAddSupplierDialog() async {
    final nameController = TextEditingController();
    final contactPersonController = TextEditingController();
    final phoneController = TextEditingController();
    final emailController = TextEditingController();
    final addressController = TextEditingController();
    final notesController = TextEditingController();
    bool isActive = true;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.business, color: AppTheme.logoPrimary, size: 28),
              const SizedBox(width: 12),
              const Text('Add Supplier / Party',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Supplier Name *',
                    hintText: 'Enter supplier/party name',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.business),
                  ),
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: contactPersonController,
                  decoration: const InputDecoration(
                    labelText: 'Contact Person',
                    hintText: 'Name of contact person',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Phone',
                    hintText: 'Phone number',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'Email address',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: addressController,
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    hintText: 'Full address',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.location_on),
                  ),
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    hintText: 'Additional notes',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.note),
                  ),
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Checkbox(
                      value: isActive,
                      onChanged: (value) {
                        setDialogState(() => isActive = value ?? true);
                      },
                    ),
                    const Text('Active'),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter supplier name')),
                  );
                  return;
                }
                Navigator.pop(context, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.logoPrimary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (result == true && nameController.text.trim().isNotEmpty) {
      try {
        final supplier = Supplier(
          name: nameController.text.trim(),
          contactPerson: contactPersonController.text.trim().isEmpty
              ? null
              : contactPersonController.text.trim(),
          phone: phoneController.text.trim().isEmpty
              ? null
              : phoneController.text.trim(),
          email: emailController.text.trim().isEmpty
              ? null
              : emailController.text.trim(),
          address: addressController.text.trim().isEmpty
              ? null
              : addressController.text.trim(),
          notes: notesController.text.trim().isEmpty
              ? null
              : notesController.text.trim(),
          isActive: isActive,
          createdAt: DateTime.now().millisecondsSinceEpoch,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );

        await _supplierService.createSupplier(
            context: context, supplier: supplier);
        await _loadSuppliers();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Supplier "${supplier.name}" added successfully'),
              backgroundColor: AppTheme.successColor,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error adding supplier: $e'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
      }
    }
  }

  Future<void> _showEditSupplierDialog(Supplier supplier) async {
    final nameController = TextEditingController(text: supplier.name);
    final contactPersonController =
        TextEditingController(text: supplier.contactPerson ?? '');
    final phoneController = TextEditingController(text: supplier.phone ?? '');
    final emailController = TextEditingController(text: supplier.email ?? '');
    final addressController =
        TextEditingController(text: supplier.address ?? '');
    final notesController = TextEditingController(text: supplier.notes ?? '');
    bool isActive = supplier.isActive;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.edit, color: AppTheme.logoPrimary, size: 28),
              const SizedBox(width: 12),
              const Text('Edit Supplier',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Supplier Name *',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.business),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: contactPersonController,
                  decoration: const InputDecoration(
                    labelText: 'Contact Person',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.person),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(
                    labelText: 'Phone',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.phone),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: addressController,
                  decoration: const InputDecoration(
                    labelText: 'Address',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.location_on),
                  ),
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.note),
                  ),
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Checkbox(
                      value: isActive,
                      onChanged: (value) {
                        setDialogState(() => isActive = value ?? true);
                      },
                    ),
                    const Text('Active'),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Cancel', style: TextStyle(color: Colors.grey[600])),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter supplier name')),
                  );
                  return;
                }
                Navigator.pop(context, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.logoPrimary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );

    if (result == true && nameController.text.trim().isNotEmpty) {
      try {
        final updatedSupplier = supplier.copyWith(
          name: nameController.text.trim(),
          contactPerson: contactPersonController.text.trim().isEmpty
              ? null
              : contactPersonController.text.trim(),
          phone: phoneController.text.trim().isEmpty
              ? null
              : phoneController.text.trim(),
          email: emailController.text.trim().isEmpty
              ? null
              : emailController.text.trim(),
          address: addressController.text.trim().isEmpty
              ? null
              : addressController.text.trim(),
          notes: notesController.text.trim().isEmpty
              ? null
              : notesController.text.trim(),
          isActive: isActive,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );

        final supplierId = kIsWeb ? supplier.documentId : supplier.id;
        await _supplierService.updateSupplier(
          context: context,
          supplierId: supplierId!,
          supplier: updatedSupplier,
        );
        await _loadSuppliers();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Supplier "${updatedSupplier.name}" updated successfully'),
              backgroundColor: AppTheme.successColor,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error updating supplier: $e'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
      }
    }
  }

  Future<void> _toggleSupplierStatus(Supplier supplier) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
            supplier.isActive ? 'Deactivate Supplier?' : 'Activate Supplier?'),
        content: Text(
          supplier.isActive
              ? 'Are you sure you want to deactivate "${supplier.name}"?'
              : 'Are you sure you want to activate "${supplier.name}"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  supplier.isActive ? Colors.orange : AppTheme.successColor,
            ),
            child: Text(supplier.isActive ? 'Deactivate' : 'Activate'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final updatedSupplier = supplier.copyWith(
          isActive: !supplier.isActive,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );

        final supplierId = kIsWeb ? supplier.documentId : supplier.id;
        await _supplierService.updateSupplier(
          context: context,
          supplierId: supplierId!,
          supplier: updatedSupplier,
        );
        await _loadSuppliers();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                supplier.isActive
                    ? 'Supplier "${supplier.name}" deactivated'
                    : 'Supplier "${supplier.name}" activated',
              ),
              backgroundColor: AppTheme.successColor,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error updating supplier: $e'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
      }
    }
  }

  Future<void> _showSupplierDetails(Supplier supplier) async {
    // Load supplier's purchases and payments
    final dbProvider =
        Provider.of<UnifiedDatabaseProvider>(context, listen: false);
    await dbProvider.init();

    List<Map<String, dynamic>> purchases = [];
    List<Map<String, dynamic>> payments = [];
    double totalPurchases = 0;
    double totalPaid = 0;
    double outstanding = 0;

    try {
      // Load purchases for this supplier
      // Prefer supplier_id linkage; fallback to supplier_name for legacy data.
      final supplierId = kIsWeb ? supplier.documentId : supplier.id;

      final Map<String, Map<String, dynamic>> byKey = {};

      if (supplierId != null) {
        try {
          final byId = await dbProvider.query(
            'purchases',
            where: 'supplier_id = ?',
            whereArgs: [supplierId],
            orderBy: 'created_at DESC',
          );
          for (final p in byId) {
            final key =
                (kIsWeb ? (p['documentId'] ?? p['id']) : p['id'])?.toString() ??
                    p.toString();
            byKey[key] = p;
          }
        } catch (e) {
          debugPrint('Error loading purchases by supplier_id: $e');
        }
      }

      // Legacy fallback (name-based)
      try {
        final byName = await dbProvider.query(
          'purchases',
          where: 'supplier_name = ?',
          whereArgs: [supplier.name],
          orderBy: 'created_at DESC',
        );
        for (final p in byName) {
          final key =
              (kIsWeb ? (p['documentId'] ?? p['id']) : p['id'])?.toString() ??
                  p.toString();
          byKey[key] = p;
        }
      } catch (e) {
        debugPrint('Error loading purchases by supplier_name: $e');
      }

      // Final fallback: tolerate mismatched spacing/case in legacy data by doing a client-side match.
      // This is especially important if older purchases stored "supplier_name" with extra spaces
      // or different casing (Firestore doesn't support easy case-insensitive equality).
      if (byKey.isEmpty) {
        try {
          final normSupplier = supplier.name.trim().toLowerCase();
          final recent = await dbProvider.query(
            'purchases',
            orderBy: 'created_at DESC',
            limit: 500,
          );
          for (final p in recent) {
            final rawName = (p['supplier_name'] as String?) ?? '';
            if (rawName.trim().toLowerCase() == normSupplier) {
              final key = (kIsWeb ? (p['documentId'] ?? p['id']) : p['id'])
                      ?.toString() ??
                  p.toString();
              byKey[key] = p;
            }
          }
        } catch (e) {
          debugPrint(
              'Error loading purchases via name-normalized fallback: $e');
        }
      }

      purchases = byKey.values.toList();
      purchases.sort((a, b) {
        final aTime = (a['created_at'] as num? ?? 0).toInt();
        final bTime = (b['created_at'] as num? ?? 0).toInt();
        return bTime.compareTo(aTime);
      });

      // Calculate totals
      for (var purchase in purchases) {
        final total = (purchase['total_amount'] as num? ?? 0).toDouble();
        final paid = (purchase['paid_amount'] as num? ?? 0).toDouble();
        totalPurchases += total;
        totalPaid += paid;
        outstanding += (total - paid);
      }

      // Load payment history
      for (var purchase in purchases) {
        final purchaseId =
            kIsWeb ? purchase['documentId'] ?? purchase['id'] : purchase['id'];
        if (purchaseId != null) {
          try {
            final purchasePayments = await dbProvider.query(
              'purchase_payments',
              where: 'purchase_id = ?',
              whereArgs: [purchaseId],
              orderBy: 'created_at DESC',
            );
            payments.addAll(purchasePayments);
          } catch (e) {
            debugPrint('Error loading payments for purchase $purchaseId: $e');
          }
        }
      }
      payments.sort((a, b) {
        final aTime = (a['created_at'] as num? ?? 0).toInt();
        final bTime = (b['created_at'] as num? ?? 0).toInt();
        return bTime.compareTo(aTime);
      });
    } catch (e) {
      debugPrint('Error loading supplier details: $e');
    }

    await showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.logoLight.withOpacity(0.3),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: AppTheme.logoPrimary,
                      child: Text(
                        supplier.name.substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            supplier.name,
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          if (supplier.phone != null)
                            Text(
                              'Phone: ${supplier.phone}',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[700]),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Summary Cards
                      Builder(
                        builder: (context) {
                          return Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildSummaryCard(
                                      'Total Purchases',
                                      totalPurchases,
                                      AppTheme.logoPrimary, // Golden yellow
                                      Icons.shopping_cart,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _buildSummaryCard(
                                      'Total Paid',
                                      totalPaid,
                                      AppTheme.successColor, // Green
                                      Icons.payment,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              _buildSummaryCard(
                                'Outstanding',
                                outstanding,
                                AppTheme.warningColor, // Darker golden
                                Icons.account_balance_wallet,
                                fullWidth: true,
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 24),

                      // Action Buttons
                      Builder(
                        builder: (dialogContext) {
                          final authProvider = Provider.of<InaraAuthProvider>(
                              context,
                              listen: false);
                          final hasOutstanding = outstanding > 0;
                          return Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.pop(dialogContext);
                                    _navigateToAddPurchase(supplier.name);
                                  },
                                  icon: const Icon(Icons.add_shopping_cart,
                                      color: Colors.white),
                                  label: const Text('Create Purchase',
                                      style: TextStyle(color: Colors.white)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.logoPrimary,
                                    foregroundColor: AppTheme.logoAccent,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                  ),
                                ),
                              ),
                              if (authProvider.isAdmin && hasOutstanding) ...[
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () async {
                                      final success =
                                          await _showSupplierPaymentDialog(
                                        supplier: supplier,
                                        purchases: purchases,
                                      );
                                      if (success) {
                                        // Close and reopen details so totals/history refresh
                                        if (Navigator.canPop(dialogContext)) {
                                          Navigator.pop(dialogContext);
                                        }
                                        await Future.delayed(
                                            const Duration(milliseconds: 150));
                                        if (mounted) {
                                          await _showSupplierDetails(supplier);
                                        }
                                      }
                                    },
                                    icon: const Icon(Icons.payments,
                                        color: Colors.white),
                                    label: const Text('Pay Supplier',
                                        style: TextStyle(color: Colors.white)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.successColor,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 24),

                      // Purchase History
                      Text(
                        'Purchase History (${purchases.length})',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (purchases.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: Text(
                              'No purchases found',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ),
                        )
                      else
                        ...purchases
                            .map((purchase) => _buildPurchaseCard(purchase)),

                      const SizedBox(height: 24),

                      // Payment History
                      Text(
                        'Payment History (${payments.length})',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (payments.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: Text(
                              'No payment transactions',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                          ),
                        )
                      else
                        ...payments.map(
                            (payment) => _buildPaymentCard(payment, purchases)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateToAddPurchase(String supplierName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            PurchasesScreen(preSelectedSupplier: supplierName),
      ),
    );
  }

  Future<bool> _showSupplierPaymentDialog({
    required Supplier supplier,
    required List<Map<String, dynamic>> purchases,
  }) async {
    final authProvider = Provider.of<InaraAuthProvider>(context, listen: false);
    if (!authProvider.isAdmin) return false;

    // Only allow payments against a specific outstanding purchase (no ambiguity)
    final outstandingPurchases = purchases.where((p) {
      final total = (p['total_amount'] as num? ?? 0).toDouble();
      final paid = (p['paid_amount'] as num? ?? 0).toDouble();
      return (total - paid) > 0;
    }).toList();

    if (outstandingPurchases.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('No outstanding purchases for this supplier')),
        );
      }
      return false;
    }

    Map<String, dynamic> selectedPurchase = outstandingPurchases.first;
    final amountController = TextEditingController();
    final notesController = TextEditingController();
    final paymentMethodNotifier = ValueNotifier<String>('cash');
    final isPartialPaymentNotifier = ValueNotifier<bool>(false);

    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          double totalAmount =
              (selectedPurchase['total_amount'] as num? ?? 0).toDouble();
          double paidAmount =
              (selectedPurchase['paid_amount'] as num? ?? 0).toDouble();
          double outstandingAmount =
              (selectedPurchase['outstanding_amount'] as num?)?.toDouble() ??
                  (totalAmount - paidAmount);
          outstandingAmount = outstandingAmount.clamp(0.0, double.infinity);

          return AlertDialog(
            title: const Text('Pay Supplier'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    supplier.name,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<Map<String, dynamic>>(
                    value: selectedPurchase,
                    decoration: const InputDecoration(
                      labelText: 'Select Purchase *',
                      border: OutlineInputBorder(),
                    ),
                    items: outstandingPurchases.map((p) {
                      final pn = p['purchase_number'] as String? ?? 'N/A';
                      final total = (p['total_amount'] as num? ?? 0).toDouble();
                      final paid = (p['paid_amount'] as num? ?? 0).toDouble();
                      final out =
                          (p['outstanding_amount'] as num?)?.toDouble() ??
                              (total - paid);
                      return DropdownMenuItem(
                        value: p,
                        child: Text(
                            '$pn • Outstanding: ${NumberFormat.currency(symbol: 'NPR ').format(out)}'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        selectedPurchase = value;
                        amountController.clear();
                        isPartialPaymentNotifier.value = false;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.warningColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.warningColor),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Outstanding:'),
                        Text(
                          NumberFormat.currency(symbol: 'NPR ')
                              .format(outstandingAmount),
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.logoAccent),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountController,
                    decoration: const InputDecoration(
                      labelText: 'Payment Amount (NPR) *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.currency_rupee),
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    autofocus: true,
                    onChanged: (value) {
                      final amount = double.tryParse(value) ?? 0;
                      setDialogState(() {
                        isPartialPaymentNotifier.value =
                            amount > 0 && amount < outstandingAmount;
                      });
                    },
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: isPartialPaymentNotifier,
                    builder: (context, isPartial, _) {
                      if (!isPartial || amountController.text.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      final amount =
                          double.tryParse(amountController.text) ?? 0;
                      final remaining = (outstandingAmount - amount)
                          .clamp(0.0, double.infinity);
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Partial payment. Remaining: ${NumberFormat.currency(symbol: 'NPR ').format(remaining)}',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[700]),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<String>(
                    valueListenable: paymentMethodNotifier,
                    builder: (context, paymentMethod, _) =>
                        DropdownButtonFormField<String>(
                      value: paymentMethod,
                      decoration: const InputDecoration(
                        labelText: 'Payment Method *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.payment),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'cash', child: Text('Cash')),
                        DropdownMenuItem(value: 'card', child: Text('Card')),
                        DropdownMenuItem(
                            value: 'bank_transfer',
                            child: Text('Bank Transfer')),
                        DropdownMenuItem(value: 'other', child: Text('Other')),
                      ],
                      onChanged: (value) {
                        paymentMethodNotifier.value = value ?? 'cash';
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesController,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.note),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final amount = double.tryParse(amountController.text) ?? 0;
                  if (amount <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Please enter a valid amount')),
                    );
                    return;
                  }
                  if (amount > outstandingAmount) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text(
                              'Amount cannot exceed outstanding ${NumberFormat.currency(symbol: 'NPR ').format(outstandingAmount)}')),
                    );
                    return;
                  }
                  Navigator.pop(context, {
                    'amount': amount,
                    'paymentMethod': paymentMethodNotifier.value,
                    'notes': notesController.text.trim(),
                    'purchase': selectedPurchase,
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.successColor,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Receive Payment'),
              ),
            ],
          );
        },
      ),
    );

    if (result == null) return false;

    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      final purchase = result['purchase'] as Map<String, dynamic>;
      final purchaseId =
          kIsWeb ? (purchase['documentId'] ?? purchase['id']) : purchase['id'];
      if (purchaseId == null) return false;

      final amount = (result['amount'] as num).toDouble();
      final paymentMethod = result['paymentMethod'] as String? ?? 'cash';
      final notes = result['notes'] as String? ?? '';
      final now = DateTime.now().millisecondsSinceEpoch;

      final totalAmount = (purchase['total_amount'] as num? ?? 0).toDouble();
      final currentPaid = (purchase['paid_amount'] as num? ?? 0).toDouble();
      final newPaid = currentPaid + amount;
      final newOutstanding =
          (totalAmount - newPaid).clamp(0.0, double.infinity);
      final newPaymentStatus =
          newOutstanding <= 0 ? 'paid' : (newPaid > 0 ? 'partial' : 'unpaid');

      // Create payment record
      await dbProvider.insert('purchase_payments', {
        'purchase_id': purchaseId,
        'amount': amount,
        'payment_method': paymentMethod,
        'notes': notes.isEmpty
            ? (newOutstanding > 0 ? 'Partial payment' : null)
            : notes,
        'created_by': authProvider.currentUserId != null
            ? (kIsWeb
                ? authProvider.currentUserId!
                : int.tryParse(authProvider.currentUserId!))
            : null,
        'created_at': now,
        'synced': 0,
      });

      // Update purchase totals
      await dbProvider.update(
        'purchases',
        values: {
          'paid_amount': newPaid,
          'outstanding_amount': newOutstanding,
          'payment_status': newPaymentStatus,
          'updated_at': now,
        },
        where: kIsWeb ? 'documentId = ?' : 'id = ?',
        whereArgs: [purchaseId],
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newOutstanding > 0
                  ? 'Partial payment received. Remaining: ${NumberFormat.currency(symbol: 'NPR ').format(newOutstanding)}'
                  : 'Payment received successfully',
            ),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }

      return true;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
      return false;
    }
  }

  Widget _buildSummaryCard(
      String label, double amount, Color color, IconData icon,
      {bool fullWidth = false}) {
    return Card(
      color: color.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    NumberFormat.currency(symbol: 'NPR ').format(amount),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPurchaseCard(Map<String, dynamic> purchase) {
    final purchaseNumber = purchase['purchase_number'] as String? ?? 'N/A';
    final totalAmount = (purchase['total_amount'] as num? ?? 0).toDouble();
    final paidAmount = (purchase['paid_amount'] as num? ?? 0).toDouble();
    final outstandingAmount = totalAmount - paidAmount;
    final createdAt = (purchase['created_at'] as num? ?? 0).toInt();
    final date = DateTime.fromMillisecondsSinceEpoch(createdAt);
    final isPaid = outstandingAmount <= 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isPaid
          ? AppTheme.successColor.withOpacity(0.1)
          : AppTheme.warningColor.withOpacity(0.1),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              isPaid ? AppTheme.successColor : AppTheme.warningColor,
          child: Icon(
            isPaid ? Icons.check_circle : Icons.pending,
            color: Colors.white,
            size: 20,
          ),
        ),
        title: Text(
          purchaseNumber,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(DateFormat('MMM dd, yyyy').format(date)),
            const SizedBox(height: 4),
            Text(
              'Total: ${NumberFormat.currency(symbol: 'NPR ').format(totalAmount)}',
              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
            ),
            if (outstandingAmount > 0)
              Text(
                'Outstanding: ${NumberFormat.currency(symbol: 'NPR ').format(outstandingAmount)}',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.warningColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
        trailing: Text(
          NumberFormat.currency(symbol: 'NPR ').format(totalAmount),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppTheme.logoPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentCard(
      Map<String, dynamic> payment, List<Map<String, dynamic>> purchases) {
    final amount = (payment['amount'] as num? ?? 0).toDouble();
    final paymentMethod = payment['payment_method'] as String? ?? 'cash';
    final notes = payment['notes'] as String? ?? '';
    final createdAt = (payment['created_at'] as num? ?? 0).toInt();
    final date = DateTime.fromMillisecondsSinceEpoch(createdAt);

    // Find purchase number
    String purchaseNumber = 'N/A';
    final purchaseId = payment['purchase_id'];
    try {
      final purchase = purchases.firstWhere(
        (p) => (kIsWeb ? (p['documentId'] ?? p['id']) : p['id']) == purchaseId,
        orElse: () => {},
      );
      purchaseNumber = purchase['purchase_number'] as String? ?? 'N/A';
    } catch (e) {
      debugPrint('Error finding purchase: $e');
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppTheme.successColor,
          child: const Icon(Icons.payment, color: Colors.white, size: 20),
        ),
        title: Text(
          'Payment for $purchaseNumber',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(DateFormat('MMM dd, yyyy HH:mm').format(date)),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.credit_card, size: 12, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  paymentMethod.toUpperCase(),
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                notes,
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
        trailing: Text(
          NumberFormat.currency(symbol: 'NPR ').format(amount),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: AppTheme.successColor,
          ),
        ),
      ),
    );
  }
}
