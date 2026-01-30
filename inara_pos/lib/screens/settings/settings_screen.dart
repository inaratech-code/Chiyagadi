import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/unified_database_provider.dart';
import '../../providers/auth_provider.dart' show InaraAuthProvider;
import '../../utils/theme.dart';
import '../../utils/app_messenger.dart';
import 'users_and_roles_management_screen.dart';

class SettingsScreen extends StatefulWidget {
  final bool showUserManagement;

  const SettingsScreen({super.key, this.showUserManagement = false});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _cafeNameController = TextEditingController();
  final _cafeNameEnController = TextEditingController();
  final _addressController = TextEditingController();
  String? _selectedDefaultDiscount;
  String? _selectedMaxDiscount;
  bool _discountEnabled = true;
  bool _isLoading = true;
  String _lockMode = 'timeout'; // 'always' | 'timeout'

  // Discount options (0% to 100%)
  final List<String> _discountOptions = List.generate(101, (i) => i.toString());

  @override
  void initState() {
    super.initState();
    // PERF: Let the screen render first.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSettings());
    if (widget.showUserManagement) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Backwards-compatible: if caller asks for user management, open the unified screen.
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const UsersAndRolesManagementScreen()),
        );
      });
    }
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      final authProvider = Provider.of<InaraAuthProvider>(context, listen: false);
      await dbProvider.init();
      final settings = await dbProvider.query('settings');

      for (final setting in settings) {
        final key = setting['key'] as String;
        final value = setting['value'] as String;
        switch (key) {
          case 'cafe_name':
            _cafeNameController.text = value;
            break;
          case 'cafe_name_en':
            _cafeNameEnController.text = value;
            break;
          case 'cafe_address':
            _addressController.text = value;
            break;
          case 'default_discount_percent':
            _selectedDefaultDiscount = value;
            break;
          case 'max_discount_percent':
            _selectedMaxDiscount = value;
            break;
          case 'discount_enabled':
            _discountEnabled = value == '1' || value.toLowerCase() == 'true';
            break;
        }
      }

      // Set defaults if not found
      if (_selectedDefaultDiscount == null) _selectedDefaultDiscount = '0';
      if (_selectedMaxDiscount == null) _selectedMaxDiscount = '50';

      // NEW: Load lock mode from InaraAuthProvider (stored in SharedPreferences)
      _lockMode = authProvider.lockMode;
    } catch (e) {
      debugPrint('Error loading settings: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      final authProvider = Provider.of<InaraAuthProvider>(context, listen: false);
      final now = DateTime.now().millisecondsSinceEpoch;

      // Update or insert settings
      final settings = [
        'cafe_name',
        'cafe_name_en',
        'cafe_address',
        if (authProvider.isAdmin) 'default_discount_percent',
        if (authProvider.isAdmin) 'max_discount_percent',
        if (authProvider.isAdmin) 'discount_enabled',
      ];
      final values = [
        _cafeNameController.text.trim(),
        _cafeNameEnController.text.trim(),
        _addressController.text.trim(),
        if (authProvider.isAdmin) _selectedDefaultDiscount ?? '0',
        if (authProvider.isAdmin) _selectedMaxDiscount ?? '50',
        if (authProvider.isAdmin) _discountEnabled ? '1' : '0',
      ];

      for (int i = 0; i < settings.length; i++) {
        final existing = await dbProvider.query(
          'settings',
          where: 'key = ?',
          whereArgs: [settings[i]],
        );

        if (existing.isNotEmpty) {
          await dbProvider.update(
            'settings',
            values: {
              'value': values[i],
              'updated_at': now,
            },
            where: 'key = ?',
            whereArgs: [settings[i]],
          );
        } else {
          await dbProvider.insert('settings', {
            'key': settings[i],
            'value': values[i],
            'updated_at': now,
          });
        }
      }

      AppMessenger.showSnackBar('Settings saved successfully');
    } catch (e) {
      AppMessenger.showSnackBar('Error: $e', backgroundColor: Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<InaraAuthProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // NEW: Security / Login behavior
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Security',
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<String>(
                            value: _lockMode,
                            decoration: const InputDecoration(
                              labelText: 'Login behavior',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'always',
                                child: Text('Ask password every time'),
                              ),
                              DropdownMenuItem(
                                value: 'timeout',
                                child: Text('Ask after long inactivity'),
                              ),
                            ],
                            onChanged: authProvider.isAdmin
                                ? (v) async {
                                    if (v == null) return;
                                    setState(() => _lockMode = v);
                                    await authProvider.setLockMode(v);
                                  }
                                : null,
                          ),
                          if (!authProvider.isAdmin)
                            const Padding(
                              padding: EdgeInsets.only(top: 8),
                              child: Text(
                                'Admin only',
                                style: TextStyle(
                                    color: Colors.grey, fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Café Information
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Café Information',
                              style: Theme.of(context).textTheme.titleLarge),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _cafeNameController,
                            decoration: const InputDecoration(
                              labelText: 'Café Name (Devanagari)',
                              hintText: 'चिया गढी',
                            ),
                          ),
                          TextField(
                            controller: _cafeNameEnController,
                            decoration: const InputDecoration(
                              labelText: 'Café Name (English)',
                              hintText: 'Chiya Gadhi',
                            ),
                          ),
                          TextField(
                            controller: _addressController,
                            decoration: const InputDecoration(
                              labelText: 'Address',
                              hintText: 'Nepal',
                            ),
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (authProvider.isAdmin) ...[
                    const SizedBox(height: 16),
                    // Discount Settings (Admin Only)
                    Card(
                      color: AppTheme.logoSecondary.withOpacity(0.1),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.local_offer,
                                    color: AppTheme.logoSecondary),
                                const SizedBox(width: 8),
                                Text(
                                  'Discount Settings',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(
                                        color: AppTheme.logoAccent,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Configure discount rules and limits',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 16),
                            SwitchListTile(
                              title: const Text('Enable Discounts'),
                              subtitle: const Text('Allow discounts on orders'),
                              value: _discountEnabled,
                              onChanged: (value) {
                                setState(() {
                                  _discountEnabled = value;
                                });
                              },
                              activeColor: AppTheme.logoPrimary,
                            ),
                            if (_discountEnabled) ...[
                              const SizedBox(height: 16),
                              DropdownButtonFormField<String>(
                                value: _selectedDefaultDiscount ?? '0',
                                decoration: const InputDecoration(
                                  labelText: 'Default Discount Percentage',
                                  border: OutlineInputBorder(),
                                  helperText:
                                      'Default discount % applied when discount is used',
                                ),
                                items: _discountOptions.map((value) {
                                  return DropdownMenuItem<String>(
                                    value: value,
                                    child: Text('$value%'),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  setState(() {
                                    _selectedDefaultDiscount = value;
                                  });
                                },
                              ),
                              const SizedBox(height: 16),
                              DropdownButtonFormField<String>(
                                value: _selectedMaxDiscount ?? '50',
                                decoration: const InputDecoration(
                                  labelText: 'Maximum Discount Percentage',
                                  border: OutlineInputBorder(),
                                  helperText: 'Maximum discount % allowed',
                                ),
                                items: _discountOptions.map((value) {
                                  return DropdownMenuItem<String>(
                                    value: value,
                                    child: Text('$value%'),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  setState(() {
                                    _selectedMaxDiscount = value;
                                  });
                                },
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  // Save Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saveSettings,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Save Settings'),
                    ),
                  ),
                  if (authProvider.isAdmin) ...[
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 16),
                    // Clear Orders Only (Admin Only)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _showResetDialog,
                        icon: const Icon(Icons.delete_sweep),
                        label: const Text('Clear Orders'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: AppTheme.errorColor,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Warning: This will permanently delete all orders, order items, and payments. Products, inventory, customers, and other data will be kept.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (authProvider.isAdmin) ...[
                    // Password Change (Admin Only)
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.lock, color: Color(0xFFFFC107)),
                                const SizedBox(width: 8),
                                Text(
                                  'Change Password',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Admin only: Change your password',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 16),
                            ListTile(
                              leading: const Icon(Icons.password),
                              title: const Text('Change My Password'),
                              subtitle: Text(
                                  'Current user: ${authProvider.currentUsername ?? 'Unknown'}'),
                              trailing:
                                  const Icon(Icons.arrow_forward_ios, size: 16),
                              onTap: () => _showChangePasswordDialog(),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Users & Roles Management (Admin Only) - Unified
                    Card(
                      color: AppTheme.logoPrimary.withOpacity(0.1),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.manage_accounts,
                                    color: AppTheme.logoPrimary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Users & Roles Management',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                          color: AppTheme.logoPrimary,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Create users, manage roles, and configure permissions all in one place',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            const UsersAndRolesManagementScreen()),
                                  );
                                },
                                icon: const Icon(Icons.settings_applications),
                                label: const Text('Manage Users & Roles'),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  backgroundColor: AppTheme.logoPrimary,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Admin Only Settings
                    Card(
                      color: AppTheme.errorColor.withOpacity(0.1),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Admin Only',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    color: AppTheme.errorColor,
                                  ),
                            ),
                            const SizedBox(height: 16),
                            ListTile(
                              leading: const Icon(Icons.delete_forever,
                                  color: AppTheme.errorColor),
                              title: const Text('Clear Orders'),
                              subtitle: const Text(
                                  'Delete all orders, order items, and payments only'),
                              onTap: () => _showResetDialog(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Future<void> _showResetDialog() async {
    final confirmController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        bool isWorking = false;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            final canConfirm =
                confirmController.text.trim().toUpperCase() == 'RESET';

            return AlertDialog(
              title: const Text('Clear Orders?'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'This will permanently delete only the order section:\n'
                      '- All orders\n'
                      '- All order items\n'
                      '- All payments\n\n'
                      'Products, inventory, customers, purchases, and other data will be kept.\n'
                      'This action cannot be undone.',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: confirmController,
                      enabled: !isWorking,
                      decoration: const InputDecoration(
                        labelText: 'Type RESET to confirm',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    if (isWorking) ...[
                      const SizedBox(height: 16),
                      const Row(
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          SizedBox(width: 12),
                          Text('Clearing data...'),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isWorking
                      ? null
                      : () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: (!canConfirm || isWorking)
                      ? null
                      : () async {
                          setDialogState(() => isWorking = true);
                          try {
                            final dbProvider =
                                Provider.of<UnifiedDatabaseProvider>(
                              dialogContext,
                              listen: false,
                            );
                            await dbProvider.clearOrdersData();
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext, true);
                            }
                          } catch (e) {
                            setDialogState(() => isWorking = false);
                            AppMessenger.showSnackBar(
                              'Error: $e',
                              backgroundColor: Colors.red,
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.errorColor,
                  ),
                  child: const Text('Clear Orders'),
                ),
              ],
            );
          },
        );
      },
    );
    confirmController.dispose();

    if (confirm == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Orders cleared successfully'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showChangePasswordDialog() async {
    final oldPinController = TextEditingController();
    final newPinController = TextEditingController();
    final confirmPinController = TextEditingController();
    bool obscureOldPin = true;
    bool obscureNewPin = true;
    bool obscureConfirmPin = true;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Change Password'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: oldPinController,
                  decoration: InputDecoration(
                    labelText: 'Current Password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(obscureOldPin
                          ? Icons.visibility
                          : Icons.visibility_off),
                      onPressed: () {
                        setDialogState(() => obscureOldPin = !obscureOldPin);
                      },
                    ),
                  ),
                  obscureText: obscureOldPin,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: newPinController,
                  decoration: InputDecoration(
                    labelText: 'New Password',
                    border: const OutlineInputBorder(),
                    helperText: '4-20 characters',
                    suffixIcon: IconButton(
                      icon: Icon(obscureNewPin
                          ? Icons.visibility
                          : Icons.visibility_off),
                      onPressed: () {
                        setDialogState(() => obscureNewPin = !obscureNewPin);
                      },
                    ),
                  ),
                  obscureText: obscureNewPin,
                  keyboardType: TextInputType.text,
                  maxLength: 20,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: confirmPinController,
                  decoration: InputDecoration(
                    labelText: 'Confirm New Password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(obscureConfirmPin
                          ? Icons.visibility
                          : Icons.visibility_off),
                      onPressed: () {
                        setDialogState(
                            () => obscureConfirmPin = !obscureConfirmPin);
                      },
                    ),
                  ),
                  obscureText: obscureConfirmPin,
                  keyboardType: TextInputType.text,
                  maxLength: 20,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Change Password'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      final oldPin = oldPinController.text.trim();
      final newPin = newPinController.text.trim();
      final confirmPin = confirmPinController.text.trim();

      if (oldPin.isEmpty || newPin.isEmpty || confirmPin.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('All fields are required')),
          );
        }
        return;
      }

      // Validate password: 4-20 characters (allows special characters)
      if (newPin.length < 4 || newPin.length > 20) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Password must be 4-20 characters')),
          );
        }
        return;
      }

      if (newPin != confirmPin) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('New passwords do not match')),
          );
        }
        return;
      }

      try {
        final authProvider = Provider.of<InaraAuthProvider>(context, listen: false);
        final success = await authProvider.changePassword(oldPin, newPin);

        if (mounted) {
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Password changed successfully'),
                backgroundColor: AppTheme.successColor,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Failed to change password. Please check your current PIN.'),
                backgroundColor: AppTheme.errorColor,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')),
          );
        }
      }
    }
  }

  // NOTE: Creating users and managing roles is handled in `UsersAndRolesManagementScreen`.
  @override
  void dispose() {
    _cafeNameController.dispose();
    _cafeNameEnController.dispose();
    _addressController.dispose();
    super.dispose();
  }
}
