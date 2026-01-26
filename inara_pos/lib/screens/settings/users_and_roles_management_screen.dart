import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart' show InaraAuthProvider;
import '../../providers/unified_database_provider.dart';
import '../../models/role.dart';
import '../../utils/theme.dart';
import 'dart:convert';

/// Unified screen for managing both users and roles
class UsersAndRolesManagementScreen extends StatefulWidget {
  const UsersAndRolesManagementScreen({super.key});

  @override
  State<UsersAndRolesManagementScreen> createState() =>
      _UsersAndRolesManagementScreenState();
}

class _UsersAndRolesManagementScreenState
    extends State<UsersAndRolesManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentTab = 0;

  // Users tab state
  bool _usersLoading = true;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _roles = [];
  String _userSearch = '';

  // Roles tab state
  bool _rolesLoading = true;
  List<Role> _rolesList = [];
  String _roleSearch = '';

  // Section names for permission selection
  final Map<int, String> _sectionNames = {
    0: 'Dashboard',
    1: 'Orders',
    2: 'Tables',
    3: 'Menu',
    4: 'Sales',
    5: 'Reports',
    6: 'Inventory',
    7: 'Customers',
    8: 'Purchases',
    9: 'Expenses',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() => _currentTab = _tabController.index);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUsers();
      _loadRoles();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ========== USERS TAB METHODS ==========

  Future<void> _loadUsers() async {
    if (!mounted) return;
    setState(() => _usersLoading = true);
    try {
      final auth = Provider.of<InaraAuthProvider>(context, listen: false);
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      // Load roles from database for user creation
      try {
        final roleMaps = await dbProvider.query(
          'roles',
          where: 'is_active = ?',
          whereArgs: [1],
          orderBy: 'name ASC',
        );
        if (mounted) {
          setState(() => _roles = roleMaps);
        }
      } catch (e) {
        debugPrint('Error loading roles (table may not exist yet): $e');
        if (mounted) {
          setState(() => _roles = [
                {'name': 'admin', 'description': 'Full system access'},
                {'name': 'cashier', 'description': 'Sales and order management'},
              ]);
        }
      }

      final users = await auth.getAllUsers();
      if (!mounted) return;
      setState(() => _users = users);
    } catch (e) {
      debugPrint('_loadUsers: Error: $e');
      if (mounted) {
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
      if (mounted) setState(() => _usersLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredUsers {
    final q = _userSearch.trim().toLowerCase();
    if (q.isEmpty) return _users;
    return _users.where((u) {
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
    String selectedRole = _roles.isNotEmpty ? _roles.first['name'] as String : 'cashier';
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
                  items: _roles.map((role) {
                    final roleName = role['name'] as String;
                    final roleDesc = role['description'] as String? ?? '';
                    return DropdownMenuItem(
                      value: roleName,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(roleName),
                          if (roleDesc.isNotEmpty)
                            Text(
                              roleDesc,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
                            ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedRole = value);
                    }
                  },
                ),
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

    if (selectedRole == 'admin' && email.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Email is required for admin users')));
      }
      return;
    }

    if (pin.length < 4 || pin.length > 20) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Password must be 4-20 characters')));
      }
      return;
    }
    if (pin != confirm) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Passwords do not match')));
      }
      return;
    }

    // UPDATED: Use createUserWithError for better error messages
    final error = await auth.createUserWithError(
      username,
      pin,
      selectedRole,
      email: selectedRole == 'admin' ? email : null,
    );
    if (!mounted) return;
    
    if (error == null) {
      // Success
      await _loadUsers();
      final createdUser = _users.firstWhere(
        (u) => u['username'] == username,
        orElse: () => {},
      );

      String message = 'User "$username" created successfully';
      if (createdUser.isNotEmpty && createdUser['email'] != null) {
        final userEmail = createdUser['email'] as String;
        message = 'User "$username" created successfully\nLogin email: $userEmail';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(message),
            backgroundColor: AppTheme.successColor,
            duration: const Duration(seconds: 5)),
      );
    } else {
      // Show specific error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5)),
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
            items: _roles.map((r) {
              final roleName = r['name'] as String;
              final roleDesc = r['description'] as String? ?? '';
              return DropdownMenuItem(
                value: roleName,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(roleName),
                    if (roleDesc.isNotEmpty)
                      Text(
                        roleDesc,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                  ],
                ),
              );
            }).toList(),
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

  Future<void> _toggleActive(Map<String, dynamic> user) async {
    final auth = Provider.of<InaraAuthProvider>(context, listen: false);
    final userId = user['id'];
    final username = user['username'] as String? ?? '';
    final isActive = _isActive(user) == 1;

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

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    final auth = Provider.of<InaraAuthProvider>(context, listen: false);
    final userId = user['id'];
    final username = user['username'] as String? ?? '';

    if (auth.currentUserId != null &&
        auth.currentUserId == userId.toString()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('You cannot delete your own account'),
              backgroundColor: Colors.red),
        );
      }
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete User?'),
        content: Text(
            'Are you sure you want to delete "$username"? This action cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    final ok = await auth.deleteUser(userId: userId);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('User "$username" deleted'),
          backgroundColor: AppTheme.successColor,
        ),
      );
      await _loadUsers();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Failed to delete user'),
            backgroundColor: Colors.red),
      );
    }
  }

  // ========== ROLES TAB METHODS ==========

  Future<void> _loadRoles() async {
    if (!mounted) return;
    setState(() => _rolesLoading = true);
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      final roleMaps = await dbProvider.query(
        'roles',
        orderBy: 'is_system_role DESC, name ASC',
      );

      // UPDATED: Ensure ID is properly set for both SQLite and Firestore
      _rolesList = roleMaps.map((map) {
        final role = Role.fromMap(map);
        // Debug: Log role data to help diagnose ID issues
        debugPrint('Loaded role: ${role.name}, id: ${role.id}, documentId: ${role.documentId}');
        return role;
      }).toList();
    } catch (e) {
      debugPrint('Error loading roles: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading roles: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _rolesLoading = false);
      }
    }
  }

  List<Role> get _filteredRoles {
    if (_roleSearch.isEmpty) return _rolesList;
    final query = _roleSearch.toLowerCase();
    return _rolesList.where((role) {
      return role.name.toLowerCase().contains(query) ||
          (role.description?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  Future<void> _showAddRoleDialog({Role? existingRole}) async {
    final nameController =
        TextEditingController(text: existingRole?.name ?? '');
    final descController =
        TextEditingController(text: existingRole?.description ?? '');
    Set<int> selectedPermissions = existingRole?.permissions ?? {0};
    bool isActive = existingRole?.isActive ?? true;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existingRole == null ? 'Create Role' : 'Edit Role'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Role Name *',
                    hintText: 'e.g., Manager, Staff, etc.',
                    border: OutlineInputBorder(),
                  ),
                  enabled: existingRole == null || !existingRole.isSystemRole,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'Brief description of this role',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Permissions *',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _sectionNames.length,
                    itemBuilder: (context, index) {
                      final sectionIndex = _sectionNames.keys.elementAt(index);
                      final sectionName = _sectionNames[sectionIndex]!;
                      final isSelected = selectedPermissions.contains(sectionIndex);
                      final isDashboard = sectionIndex == 0;

                      return CheckboxListTile(
                        title: Text(sectionName),
                        value: isSelected,
                        enabled: !isDashboard,
                        onChanged: isDashboard
                            ? null
                            : (value) {
                                setDialogState(() {
                                  if (value == true) {
                                    selectedPermissions.add(sectionIndex);
                                  } else {
                                    selectedPermissions.remove(sectionIndex);
                                    if (selectedPermissions.isEmpty) {
                                      selectedPermissions.add(0);
                                    }
                                  }
                                });
                              },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  title: const Text('Active'),
                  value: isActive,
                  onChanged: (value) {
                    setDialogState(() => isActive = value ?? true);
                  },
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
              child: Text(existingRole == null ? 'Create' : 'Update'),
            ),
          ],
        ),
      ),
    );

    if (result == true && nameController.text.trim().isNotEmpty) {
      try {
        final dbProvider =
            Provider.of<UnifiedDatabaseProvider>(context, listen: false);
        await dbProvider.init();

        final roleName = nameController.text.trim();
        final now = DateTime.now().millisecondsSinceEpoch;

        if (!selectedPermissions.contains(0)) {
          selectedPermissions.add(0);
        }

        if (selectedPermissions.length < 2) {
          selectedPermissions.add(1);
        }

        if (existingRole == null) {
          final existing = await dbProvider.query(
            'roles',
            where: 'name = ?',
            whereArgs: [roleName],
          );

          if (existing.isNotEmpty) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Role with this name already exists'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            return;
          }

          final roleId = await dbProvider.insert('roles', {
            'name': roleName,
            'description': descController.text.trim().isEmpty
                ? null
                : descController.text.trim(),
            'permissions': jsonEncode(selectedPermissions.toList()),
            'is_system_role': 0,
            'is_active': isActive ? 1 : 0,
            'created_at': now,
            'updated_at': now,
          });

          if (roleId != null) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Role created successfully'),
                  backgroundColor: Colors.green,
                ),
              );
            }
            await _loadRoles();
            await _loadUsers(); // Refresh users to get updated roles
          }
        } else {
          // UPDATED: Better handling of role ID for both SQLite and Firestore
          dynamic roleId;
          String whereClause;
          
          if (kIsWeb) {
            // Firestore uses documentId
            roleId = existingRole.documentId;
            whereClause = 'documentId = ?';
            if (roleId == null) {
              // Fallback: try to find by name if documentId is missing
              debugPrint('Warning: Role documentId is null, attempting to find by name');
              final found = await dbProvider.query(
                'roles',
                where: 'name = ?',
                whereArgs: [existingRole.name],
              );
              if (found.isNotEmpty) {
                roleId = found.first['documentId'];
                if (roleId == null) {
                  throw Exception('Role ID is required for update. Role "${existingRole.name}" found but has no ID.');
                }
              } else {
                throw Exception('Role ID is required for update. Role "${existingRole.name}" not found in database.');
              }
            }
          } else {
            // SQLite uses id
            roleId = existingRole.id;
            whereClause = 'id = ?';
            if (roleId == null) {
              // Fallback: try to find by name if id is missing
              debugPrint('Warning: Role id is null, attempting to find by name');
              final found = await dbProvider.query(
                'roles',
                where: 'name = ?',
                whereArgs: [existingRole.name],
              );
              if (found.isNotEmpty) {
                roleId = found.first['id'];
                if (roleId == null) {
                  throw Exception('Role ID is required for update. Role "${existingRole.name}" found but has no ID.');
                }
              } else {
                throw Exception('Role ID is required for update. Role "${existingRole.name}" not found in database.');
              }
            }
          }

          if (roleName != existingRole.name) {
            final existing = await dbProvider.query(
              'roles',
              where: 'name = ?',
              whereArgs: [roleName],
            );

            if (existing.isNotEmpty) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Role with this name already exists'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
              return;
            }
          }

          await dbProvider.update(
            'roles',
            values: {
              'name': roleName,
              'description': descController.text.trim().isEmpty
                  ? null
                  : descController.text.trim(),
              'permissions': jsonEncode(selectedPermissions.toList()),
              'is_active': isActive ? 1 : 0,
              'updated_at': now,
            },
            where: whereClause,
            whereArgs: [roleId],
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Role updated successfully'),
                backgroundColor: Colors.green,
              ),
            );
          }
          await _loadRoles();
          await _loadUsers(); // Refresh users to get updated roles
        }
      } catch (e) {
        debugPrint('Error saving role: $e');
        if (mounted) {
          String errorMessage = 'Error saving role';
          final errorStr = e.toString();
          
          // UPDATED: More user-friendly error messages
          if (errorStr.contains('Role ID is required')) {
            errorMessage = 'Unable to update role. Please refresh the page and try again.';
          } else if (errorStr.contains('already exists')) {
            errorMessage = 'A role with this name already exists. Please choose a different name.';
          } else {
            errorMessage = 'Error saving role: ${errorStr.length > 100 ? errorStr.substring(0, 100) + "..." : errorStr}';
          }
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteRole(Role role) async {
    if (role.isSystemRole) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('System roles cannot be deleted'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      final users = await dbProvider.query(
        'users',
        where: 'role = ?',
        whereArgs: [role.name],
      );

      if (users.isNotEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                  'Cannot delete role: ${users.length} user(s) are using this role'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete Role?'),
          content: Text('Are you sure you want to delete "${role.name}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        ),
      );

      if (confirm == true) {
        // UPDATED: Better handling of role ID for deletion
        dynamic roleId;
        String whereClause;
        
        if (kIsWeb) {
          roleId = role.documentId;
          whereClause = 'documentId = ?';
        } else {
          roleId = role.id;
          whereClause = 'id = ?';
        }
        
        if (roleId == null) {
          // Fallback: try to find by name
          debugPrint('Warning: Role ID is null for deletion, attempting to find by name');
          final found = await dbProvider.query(
            'roles',
            where: 'name = ?',
            whereArgs: [role.name],
          );
          if (found.isNotEmpty) {
            roleId = kIsWeb ? found.first['documentId'] : found.first['id'];
            if (roleId == null) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Cannot delete role: "${role.name}" - ID not found'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
              return;
            }
          } else {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Cannot delete role: "${role.name}" - not found in database'),
                  backgroundColor: Colors.red,
                ),
              );
            }
            return;
          }
        }

        await dbProvider.delete(
          'roles',
          where: whereClause,
          whereArgs: [roleId],
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Role deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
        await _loadRoles();
        await _loadUsers(); // Refresh users
      }
    } catch (e) {
      debugPrint('Error deleting role: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting role: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ========== BUILD METHODS ==========

  Widget _buildUsersTab() {
    final auth = Provider.of<InaraAuthProvider>(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Search users',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _userSearch = v),
          ),
        ),
        Expanded(
          child: _usersLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredUsers.isEmpty
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
                                      color: AppTheme.logoLight.withOpacity(0.25),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: const Text('You',
                                        style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600)),
                                  ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (u['email'] != null &&
                                    (u['email'] as String).isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.email_outlined,
                                          size: 14,
                                          color: Colors.grey[600],
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            u['email'] as String,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[700],
                                              fontWeight: FontWeight.w500,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: roleColor.withOpacity(0.12),
                                        borderRadius: BorderRadius.circular(999),
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
                                        borderRadius: BorderRadius.circular(999),
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
                                if (value == 'delete') {
                                  await _deleteUser(u);
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
                                const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete User',
                                        style: TextStyle(color: Colors.red))),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildRolesTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search roles...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _roleSearch.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        setState(() => _roleSearch = '');
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onChanged: (value) {
              setState(() => _roleSearch = value);
            },
          ),
        ),
        Expanded(
          child: _rolesLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredRoles.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.people_outline,
                              size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            _roleSearch.isEmpty
                                ? 'No roles found'
                                : 'No roles match your search',
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _filteredRoles.length,
                      itemBuilder: (context, index) {
                        final role = _filteredRoles[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: role.isSystemRole
                                  ? Colors.blue
                                  : AppTheme.logoPrimary,
                              child: Icon(
                                role.isSystemRole
                                    ? Icons.security
                                    : Icons.person,
                                color: Colors.white,
                              ),
                            ),
                            title: Row(
                              children: [
                                Text(
                                  role.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (role.isSystemRole) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.blue[100],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'System',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.blue,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                                if (!role.isActive) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.grey[300],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'Inactive',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.grey,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (role.description != null &&
                                    role.description!.isNotEmpty)
                                  Text(role.description!),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: role.permissions
                                      .map((perm) => Chip(
                                            label: Text(
                                              _sectionNames[perm] ?? 'Unknown',
                                              style: const TextStyle(
                                                  fontSize: 11),
                                            ),
                                            padding: EdgeInsets.zero,
                                            materialTapTargetSize:
                                                MaterialTapTargetSize
                                                    .shrinkWrap,
                                            visualDensity:
                                                VisualDensity.compact,
                                          ))
                                      .toList(),
                                ),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () =>
                                      _showAddRoleDialog(existingRole: role),
                                  tooltip: 'Edit Role',
                                ),
                                if (!role.isSystemRole)
                                  IconButton(
                                    icon: const Icon(Icons.delete,
                                        color: Colors.red),
                                    onPressed: () => _deleteRole(role),
                                    tooltip: 'Delete Role',
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
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
      appBar: AppBar(
        title: const Text('Users & Roles Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              if (_currentTab == 0) {
                _loadUsers();
              } else {
                _loadRoles();
              }
            },
            tooltip: 'Refresh',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.people), text: 'Users'),
            Tab(icon: Icon(Icons.security), text: 'Roles'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildUsersTab(),
          _buildRolesTab(),
        ],
      ),
      floatingActionButton: _currentTab == 0
          ? FloatingActionButton.extended(
              onPressed: _showAddUserDialog,
              backgroundColor: AppTheme.logoPrimary,
              foregroundColor: AppTheme.logoAccent,
              icon: const Icon(Icons.person_add),
              label: const Text('Add User'),
            )
          : FloatingActionButton.extended(
              onPressed: () => _showAddRoleDialog(),
              backgroundColor: AppTheme.logoSecondary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Create Role'),
            ),
    );
  }
}
