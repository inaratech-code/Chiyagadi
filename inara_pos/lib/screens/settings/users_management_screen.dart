import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart' show InaraAuthProvider;
import '../../utils/theme.dart';

class UsersManagementScreen extends StatefulWidget {
  const UsersManagementScreen({super.key});

  @override
  State<UsersManagementScreen> createState() => _UsersManagementScreenState();
}

class _UsersManagementScreenState extends State<UsersManagementScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _users = [];
  String _search = '';

  @override
  void initState() {
    super.initState();
    // PERF: Let the screen render first.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadUsers());
  }

  Future<void> _loadUsers() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final auth = Provider.of<InaraAuthProvider>(context, listen: false);
      final users = await auth.getAllUsers();
      if (!mounted) return;
      setState(() => _users = users);
      
      // Show a helpful message if database initialization failed but we have at least the current user
      if (users.isEmpty && auth.isAuthenticated && auth.isAdmin) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Database initialization failed. Showing current user only.'),
              duration: Duration(seconds: 3),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('_loadUsers: Error: $e');
      if (mounted) {
        // Don't show error if it's just a database init issue - getAllUsers handles it gracefully
        final errorStr = e.toString();
        if (!errorStr.contains('Database initialization failed') && 
            !errorStr.contains('Null check')) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error loading users: $e'),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredUsers {
    final q = _search.trim().toLowerCase();
    final list = _users;
    if (q.isEmpty) return list;
    return list.where((u) {
      final username = (u['username'] as String? ?? '').toLowerCase();
      final role = (u['role'] as String? ?? '').toLowerCase();
      return username.contains(q) || role.contains(q);
    }).toList();
  }

  int _isActive(Map<String, dynamic> u) =>
      (u['is_active'] as num?)?.toInt() ?? 1;

  Future<void> _showAddUserDialog() async {
    final auth = Provider.of<InaraAuthProvider>(context, listen: false);
    final usernameController = TextEditingController();
    final emailController = TextEditingController();
    final pinController = TextEditingController();
    final confirmPinController = TextEditingController();
    String selectedRole = 'cashier';
    bool obscurePin = true;
    bool obscureConfirmPin = true;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create User'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedRole,
                  decoration: const InputDecoration(
                    labelText: 'Role',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                    DropdownMenuItem(value: 'cashier', child: Text('Cashier')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedRole = value);
                    }
                  },
                ),
                // Email field - only shown and required for admin role
                // For cashiers, email will be auto-generated
                if (selectedRole == 'admin') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email *',
                      border: OutlineInputBorder(),
                      helperText: 'Required for admin users',
                    ),
                  ),
                ] else if (selectedRole == 'cashier') ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Email will be auto-generated for cashier login',
                            style: TextStyle(
                              color: Colors.blue[900],
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: pinController,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    border: const OutlineInputBorder(),
                    helperText: '4-20 characters',
                    suffixIcon: IconButton(
                      icon: Icon(
                          obscurePin ? Icons.visibility : Icons.visibility_off),
                      onPressed: () =>
                          setDialogState(() => obscurePin = !obscurePin),
                    ),
                  ),
                  obscureText: obscurePin,
                  keyboardType: TextInputType.text,
                  maxLength: 20,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmPinController,
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(obscureConfirmPin
                          ? Icons.visibility
                          : Icons.visibility_off),
                      onPressed: () => setDialogState(
                          () => obscureConfirmPin = !obscureConfirmPin),
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
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Create')),
          ],
        ),
      ),
    );

    if (result != true) return;

    final username = usernameController.text.trim();
    final email = emailController.text.trim();
    final pin = pinController.text.trim();
    final confirm = confirmPinController.text.trim();

    if (username.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Username is required')));
      }
      return;
    }
    
    // Email is required only for admin role
    if (selectedRole == 'admin' && email.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Email is required for admin users')));
      }
      return;
    }
    
    // Validate password: 4-20 characters
    if (pin.length < 4 || pin.length > 20) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Password must be 4-20 characters')));
      }
      return;
    }
    if (pin != confirm) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Passwords do not match')));
      }
      return;
    }

    final ok = await auth.createUser(
      username,
      pin,
      selectedRole,
      email: selectedRole == 'admin' ? email : null,
    );
    if (!mounted) return;
    if (ok) {
      // For cashiers, show the generated email
      String message = 'User "$username" created';
      if (selectedRole == 'cashier') {
        // Get the generated email from the user list
        await _loadUsers();
        final createdUser = _users.firstWhere(
          (u) => u['username'] == username,
          orElse: () => {},
        );
        if (createdUser.isNotEmpty && createdUser['email'] != null) {
          message = 'User "$username" created\nLogin email: ${createdUser['email']}';
        }
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(message),
            backgroundColor: AppTheme.successColor,
            duration: const Duration(seconds: 5)),
      );
      await _loadUsers();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Failed to create user (username may exist)'),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _showResetPinDialog(Map<String, dynamic> user) async {
    final auth = Provider.of<InaraAuthProvider>(context, listen: false);
    final userId = user['id'];
    final username = user['username'] as String? ?? '';
    final pinController = TextEditingController();
    final confirmController = TextEditingController();
    bool obscurePin = true;
    bool obscureConfirm = true;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Reset PIN: $username'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pinController,
                decoration: InputDecoration(
                  labelText: 'New Password',
                  border: const OutlineInputBorder(),
                  helperText: '4-20 characters (letters and numbers)',
                  suffixIcon: IconButton(
                    icon: Icon(
                        obscurePin ? Icons.visibility : Icons.visibility_off),
                    onPressed: () =>
                        setDialogState(() => obscurePin = !obscurePin),
                  ),
                ),
                obscureText: obscurePin,
                keyboardType: TextInputType.text,
                maxLength: 20,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmController,
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(obscureConfirm
                        ? Icons.visibility
                        : Icons.visibility_off),
                    onPressed: () =>
                        setDialogState(() => obscureConfirm = !obscureConfirm),
                  ),
                ),
                obscureText: obscureConfirm,
                keyboardType: TextInputType.text,
                maxLength: 20,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Reset')),
          ],
        ),
      ),
    );

    if (result != true) return;
    final pin = pinController.text.trim();
    final confirm = confirmController.text.trim();
    // Validate password: 4-20 characters
    if (pin.length < 4 || pin.length > 20) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Password must be 4-20 characters')));
      }
      return;
    }
    if (pin != confirm) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Passwords do not match')));
      }
      return;
    }

    final ok = await auth.resetUserPin(userId: userId, newPin: pin);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('PIN reset for "$username"'),
            backgroundColor: AppTheme.successColor),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Failed to reset PIN'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _showChangeRoleDialog(Map<String, dynamic> user) async {
    final auth = Provider.of<InaraAuthProvider>(context, listen: false);
    final userId = user['id'];
    final username = user['username'] as String? ?? '';
    String role = user['role'] as String? ?? 'cashier';

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Change Role: $username'),
          content: DropdownButtonFormField<String>(
            value: role,
            decoration: const InputDecoration(
                border: OutlineInputBorder(), labelText: 'Role'),
            items: const [
              DropdownMenuItem(value: 'admin', child: Text('Admin')),
              DropdownMenuItem(value: 'cashier', child: Text('Cashier')),
            ],
            onChanged: (v) => setDialogState(() => role = v ?? role),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Save')),
          ],
        ),
      ),
    );

    if (result != true) return;
    final ok = await auth.updateUserRole(userId: userId, role: role);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Role updated for "$username"'),
            backgroundColor: AppTheme.successColor),
      );
      await _loadUsers();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Failed to update role'),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _showRolePermissionsDialog() async {
    final auth = Provider.of<InaraAuthProvider>(context, listen: false);
    
    // Section names and indices
    final sections = [
      {'name': 'Dashboard', 'index': 0},
      {'name': 'Orders', 'index': 1},
      {'name': 'Tables', 'index': 2},
      {'name': 'Menu', 'index': 3},
      {'name': 'Sales', 'index': 4},
      {'name': 'Reports', 'index': 5},
      {'name': 'Inventory', 'index': 6},
      {'name': 'Customers', 'index': 7},
      {'name': 'Purchases', 'index': 8},
      {'name': 'Expenses', 'index': 9},
    ];

    // Load current permissions
    Set<int> adminPermissions = await auth.getRolePermissions('admin');
    Set<int> cashierPermissions = await auth.getRolePermissions('cashier');
    
    // Ensure Dashboard (0) is always included
    adminPermissions.add(0);
    cashierPermissions.add(0);
    
    // Ensure at least 2 permissions (Dashboard + one other)
    if (adminPermissions.length < 2 && !adminPermissions.contains(1)) {
      adminPermissions.add(1); // Add Orders as default second option
    }
    if (cashierPermissions.length < 2 && !cashierPermissions.contains(1)) {
      cashierPermissions.add(1); // Add Orders as default second option
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Role Permissions'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Admin Permissions
                Text(
                  'Admin Permissions',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.logoPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                ...sections.map((section) {
                  final index = section['index'] as int;
                  final isSelected = adminPermissions.contains(index);
                  final isDashboard = index == 0;
                  return CheckboxListTile(
                    title: Text(section['name'] as String),
                    value: isSelected,
                    onChanged: isDashboard
                        ? null // Dashboard cannot be unchecked
                        : (value) {
                            setDialogState(() {
                              if (value == true) {
                                adminPermissions.add(index);
                              } else {
                                // Ensure at least Dashboard + one other section
                                adminPermissions.remove(index);
                                if (adminPermissions.length < 2) {
                                  // Keep Dashboard and add Orders if not already there
                                  adminPermissions.add(0);
                                  if (!adminPermissions.contains(1)) {
                                    adminPermissions.add(1);
                                  }
                                }
                              }
                            });
                          },
                    dense: true,
                    subtitle: isDashboard
                        ? const Text('Always enabled (required)', style: TextStyle(fontSize: 11))
                        : null,
                  );
                }),
                const Divider(height: 32),
                // Cashier Permissions
                Text(
                  'Cashier Permissions',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF6C5CE7),
                  ),
                ),
                const SizedBox(height: 8),
                ...sections.map((section) {
                  final index = section['index'] as int;
                  final isSelected = cashierPermissions.contains(index);
                  final isDashboard = index == 0;
                  return CheckboxListTile(
                    title: Text(section['name'] as String),
                    value: isSelected,
                    onChanged: isDashboard
                        ? null // Dashboard cannot be unchecked
                        : (value) {
                            setDialogState(() {
                              if (value == true) {
                                cashierPermissions.add(index);
                              } else {
                                // Ensure at least Dashboard + one other section
                                cashierPermissions.remove(index);
                                if (cashierPermissions.length < 2) {
                                  // Keep Dashboard and add Orders if not already there
                                  cashierPermissions.add(0);
                                  if (!cashierPermissions.contains(1)) {
                                    cashierPermissions.add(1);
                                  }
                                }
                              }
                            });
                          },
                    dense: true,
                    subtitle: isDashboard
                        ? const Text('Always enabled (required)', style: TextStyle(fontSize: 11))
                        : null,
                  );
                }),
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
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      // Save permissions
      final adminOk = await auth.updateRolePermissions('admin', adminPermissions);
      final cashierOk = await auth.updateRolePermissions('cashier', cashierPermissions);

      if (mounted) {
        if (adminOk && cashierOk) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Role permissions updated successfully'),
              backgroundColor: AppTheme.successColor,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to update permissions'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _toggleActive(Map<String, dynamic> user) async {
    final auth = Provider.of<InaraAuthProvider>(context, listen: false);
    final userId = user['id'];
    final username = user['username'] as String? ?? '';
    final isActive = _isActive(user) == 1;

    // Don't allow disabling yourself
    if (auth.currentUserId != null &&
        auth.currentUserId == userId.toString() &&
        isActive) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('You cannot disable your own account'),
              backgroundColor: Colors.red),
        );
      }
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isActive ? 'Disable User?' : 'Enable User?'),
        content: Text(isActive
            ? 'Disable "$username"? They will not be able to login.'
            : 'Enable "$username"? They will be able to login again.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor:
                    isActive ? AppTheme.warningColor : AppTheme.successColor),
            child: Text(isActive ? 'Disable' : 'Enable'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    final ok = await auth.setUserActive(userId: userId, isActive: !isActive);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isActive ? 'User disabled' : 'User enabled'),
          backgroundColor: AppTheme.successColor,
        ),
      );
      await _loadUsers();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Failed to update user status'),
            backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<InaraAuthProvider>(context);
    if (!auth.isAdmin) {
      return const Scaffold(
        body: Center(child: Text('Admin access required')),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFFFEF5),
      appBar: AppBar(
        title: const Text('User Management'),
        actions: [
          IconButton(
            onPressed: _loadUsers,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.extended(
            onPressed: _showRolePermissionsDialog,
            backgroundColor: AppTheme.logoSecondary,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.security),
            label: const Text('Role Permissions'),
            heroTag: 'permissions',
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            onPressed: _showAddUserDialog,
            backgroundColor: AppTheme.logoPrimary,
            foregroundColor: AppTheme.logoAccent,
            icon: const Icon(Icons.person_add),
            label: const Text('Add User'),
            heroTag: 'add_user',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Search users',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
                Expanded(
                  child: _filteredUsers.isEmpty
                      ? const Center(child: Text('No users found'))
                      : ListView.builder(
                          itemCount: _filteredUsers.length,
                          itemBuilder: (context, index) {
                            final u = _filteredUsers[index];
                            final username =
                                u['username'] as String? ?? 'Unknown';
                            final role = u['role'] as String? ?? 'cashier';
                            final active = _isActive(u) == 1;
                            final isMe = auth.currentUserId != null &&
                                auth.currentUserId == u['id'].toString();

                            final roleColor = role == 'admin'
                                ? AppTheme.logoPrimary
                                : const Color(0xFF6C5CE7);
                            final statusColor = active
                                ? AppTheme.successColor
                                : AppTheme.warningColor;

                            return Card(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 6),
                              color: Colors.white,
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: roleColor.withOpacity(0.15),
                                  child: Icon(
                                    role == 'admin'
                                        ? Icons.admin_panel_settings
                                        : Icons.point_of_sale,
                                    color: roleColor,
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        username,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                    if (isMe)
                                      Container(
                                        margin: const EdgeInsets.only(left: 8),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.logoLight
                                              .withOpacity(0.25),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: const Text('You',
                                            style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600)),
                                      ),
                                  ],
                                ),
                                subtitle: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: roleColor.withOpacity(0.12),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        role.toUpperCase(),
                                        style: TextStyle(
                                            color: roleColor,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: statusColor.withOpacity(0.12),
                                        borderRadius:
                                            BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        active ? 'ACTIVE' : 'DISABLED',
                                        style: TextStyle(
                                            color: statusColor,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (value) async {
                                    if (value == 'pin') {
                                      await _showResetPinDialog(u);
                                    }
                                    if (value == 'role') {
                                      await _showChangeRoleDialog(u);
                                    }
                                    if (value == 'active') {
                                      await _toggleActive(u);
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                        value: 'pin', child: Text('Reset PIN')),
                                    const PopupMenuItem(
                                        value: 'role',
                                        child: Text('Change Role')),
                                    PopupMenuItem(
                                        value: 'active',
                                        child: Text(active
                                            ? 'Disable User'
                                            : 'Enable User')),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
