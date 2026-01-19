import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/unified_database_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../utils/theme.dart';
import '../../utils/app_messenger.dart';
import 'users_management_screen.dart';

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
  final _vatPercentController = TextEditingController();
  String? _selectedDefaultDiscount;
  String? _selectedMaxDiscount;
  bool _discountEnabled = true;
  bool _isLoading = true;

  // Discount options (0% to 100%)
  final List<String> _discountOptions = List.generate(101, (i) => i.toString());

  @override
  void initState() {
    super.initState();
    _loadSettings();
    if (widget.showUserManagement) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Backwards-compatible: if caller asks for user management, open the full screen.
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const UsersManagementScreen()),
        );
      });
    }
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
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
          case 'tax_percent':
          case 'vat_percent':
            _vatPercentController.text = value;
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
      if (_vatPercentController.text.trim().isEmpty) {
        _vatPercentController.text = '13';
      }
      if (_selectedDefaultDiscount == null) _selectedDefaultDiscount = '0';
      if (_selectedMaxDiscount == null) _selectedMaxDiscount = '50';
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
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final now = DateTime.now().millisecondsSinceEpoch;

      // Validate VAT percent (admin only can modify, but we still validate on save)
      final vatRaw = _vatPercentController.text.trim();
      final vatParsed = double.tryParse(vatRaw);
      if (vatParsed == null || vatParsed < 0 || vatParsed > 100) {
        AppMessenger.showSnackBar('Please enter a valid VAT % (0 to 100)');
        return;
      }

      // Update or insert settings
      final settings = [
        'cafe_name',
        'cafe_name_en',
        'cafe_address',
        'tax_percent',
        if (authProvider.isAdmin) 'default_discount_percent',
        if (authProvider.isAdmin) 'max_discount_percent',
        if (authProvider.isAdmin) 'discount_enabled',
      ];
      final values = [
        _cafeNameController.text.trim(),
        _cafeNameEnController.text.trim(),
        _addressController.text.trim(),
        // Store as string (works for SQLite + Firestore) and allow decimals
        vatParsed.toString(),
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
    final authProvider = Provider.of<AuthProvider>(context);

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
                  const SizedBox(height: 16),
                  // Theme Settings
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.dark_mode,
                                  color: Color(0xFFFFC107)),
                              const SizedBox(width: 8),
                              Text(
                                'Appearance',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Consumer<ThemeProvider>(
                            builder: (context, themeProvider, _) {
                              return Column(
                                children: [
                                  RadioListTile<ThemeMode>(
                                    title: const Text('System Default'),
                                    subtitle: const Text('Follow device theme'),
                                    value: ThemeMode.system,
                                    groupValue: themeProvider.themeMode,
                                    onChanged: (value) {
                                      if (value != null) {
                                        themeProvider.setThemeMode(value);
                                      }
                                    },
                                  ),
                                  RadioListTile<ThemeMode>(
                                    title: const Text('Light Mode'),
                                    subtitle:
                                        const Text('Always use light theme'),
                                    value: ThemeMode.light,
                                    groupValue: themeProvider.themeMode,
                                    onChanged: (value) {
                                      if (value != null) {
                                        themeProvider.setThemeMode(value);
                                      }
                                    },
                                  ),
                                  RadioListTile<ThemeMode>(
                                    title: const Text('Dark Mode'),
                                    subtitle:
                                        const Text('Always use dark theme'),
                                    value: ThemeMode.dark,
                                    groupValue: themeProvider.themeMode,
                                    onChanged: (value) {
                                      if (value != null) {
                                        themeProvider.setThemeMode(value);
                                      }
                                    },
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // VAT Settings (Visible to All, Editable by Admin Only)
                  Card(
                    color: AppTheme.logoPrimary.withOpacity(0.1),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.receipt_long,
                                  color: AppTheme.logoPrimary),
                              const SizedBox(width: 8),
                              Text(
                                'VAT Settings',
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
                            'Configure Value Added Tax (VAT) percentage',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _vatPercentController,
                            // Allow VAT editing for all users (requested).
                            enabled: true,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                              labelText: 'VAT % (manual)',
                              border: OutlineInputBorder(),
                              helperText:
                                  'Example: 13 (Nepal default). You can set 0–100 and decimals (e.g., 13.5).',
                            ),
                          ),
                          // Discounts remain admin-only below.
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
                  // Password Change (All Users)
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
                  if (authProvider.isAdmin) ...[
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
                              leading: const Icon(Icons.manage_accounts,
                                  color: AppTheme.logoPrimary),
                              title: const Text('User Management'),
                              subtitle: const Text(
                                  'Create users, reset PINs, roles (Admin/Cashier)'),
                              trailing:
                                  const Icon(Icons.arrow_forward_ios, size: 16),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const UsersManagementScreen()),
                                );
                              },
                            ),
                            const Divider(),
                            ListTile(
                              leading: const Icon(Icons.delete_forever,
                                  color: AppTheme.errorColor),
                              title: const Text('Clear App Data'),
                              subtitle: const Text(
                                  'Delete all business data entered through the app'),
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
              title: const Text('Clear App Data?'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'This will permanently delete business data entered through the app, including:\n'
                      '- Orders, payments, and credit records\n'
                      '- Products and categories\n'
                      '- Inventory, stock transactions, inventory ledger\n'
                      '- Purchases, suppliers, and purchase payments\n'
                      '- Customers and expenses\n'
                      '- Tables, day sessions, sync queue, and audit logs\n\n'
                      'Users and settings will be kept.\n'
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
                            await dbProvider.clearBusinessData(
                                seedDefaults: true);
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
                  child: const Text('Clear Data'),
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
          content: Text('App data cleared successfully'),
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
                    labelText: 'Current PIN',
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
                    labelText: 'New PIN',
                    border: const OutlineInputBorder(),
                    helperText: '4-6 digits',
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
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: confirmPinController,
                  decoration: InputDecoration(
                    labelText: 'Confirm New PIN',
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
                  keyboardType: TextInputType.number,
                  maxLength: 6,
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

      if (newPin.length < 4 || newPin.length > 6) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PIN must be 4-6 digits')),
          );
        }
        return;
      }

      if (newPin != confirmPin) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('New PINs do not match')),
          );
        }
        return;
      }

      try {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
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

  // NOTE: Creating users is handled in `UsersManagementScreen`.
  @override
  void dispose() {
    _cafeNameController.dispose();
    _cafeNameEnController.dispose();
    _addressController.dispose();
    _vatPercentController.dispose();
    super.dispose();
  }
}
