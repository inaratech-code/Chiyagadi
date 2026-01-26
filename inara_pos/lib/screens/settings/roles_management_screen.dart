import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:provider/provider.dart';
import '../../providers/unified_database_provider.dart';
import '../../providers/auth_provider.dart' show InaraAuthProvider;
import '../../models/role.dart';
import '../../utils/theme.dart';
import 'dart:convert';

class RolesManagementScreen extends StatefulWidget {
  const RolesManagementScreen({super.key});

  @override
  State<RolesManagementScreen> createState() => _RolesManagementScreenState();
}

class _RolesManagementScreenState extends State<RolesManagementScreen> {
  List<Role> _roles = [];
  bool _isLoading = true;
  String _searchQuery = '';

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadRoles());
  }

  Future<void> _loadRoles() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      final roleMaps = await dbProvider.query(
        'roles',
        orderBy: 'is_system_role DESC, name ASC',
      );

      _roles = roleMaps.map((map) => Role.fromMap(map)).toList();
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
        setState(() => _isLoading = false);
      }
    }
  }

  List<Role> get _filteredRoles {
    if (_searchQuery.isEmpty) return _roles;
    final query = _searchQuery.toLowerCase();
    return _roles.where((role) {
      return role.name.toLowerCase().contains(query) ||
          (role.description?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  Future<void> _showAddRoleDialog({Role? existingRole}) async {
    final nameController =
        TextEditingController(text: existingRole?.name ?? '');
    final descController =
        TextEditingController(text: existingRole?.description ?? '');
    Set<int> selectedPermissions = existingRole?.permissions ?? {0}; // Default: Dashboard only
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
                        enabled: !isDashboard, // Dashboard is always enabled
                        onChanged: isDashboard
                            ? null
                            : (value) {
                                setDialogState(() {
                                  if (value == true) {
                                    selectedPermissions.add(sectionIndex);
                                  } else {
                                    selectedPermissions.remove(sectionIndex);
                                    // Ensure at least Dashboard is selected
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

        // Ensure Dashboard is always included
        if (!selectedPermissions.contains(0)) {
          selectedPermissions.add(0);
        }

        // Ensure at least 2 permissions
        if (selectedPermissions.length < 2) {
          selectedPermissions.add(1); // Add Orders as default
        }

        if (existingRole == null) {
          // Create new role
          // Check if role name already exists
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
          }
        } else {
          // Update existing role
          final roleId = kIsWeb ? existingRole.documentId : existingRole.id;
          if (roleId == null) {
            throw Exception('Role ID is required for update');
          }

          // Check if name changed and conflicts with another role
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
            where: kIsWeb ? 'documentId = ?' : 'id = ?',
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
        }
      } catch (e) {
        debugPrint('Error saving role: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error saving role: $e'),
              backgroundColor: Colors.red,
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

    // Check if any users are using this role
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
        final roleId = kIsWeb ? role.documentId : role.id;
        if (roleId == null) return;

        await dbProvider.delete(
          'roles',
          where: kIsWeb ? 'documentId = ?' : 'id = ?',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Roles Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRoles,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search roles...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
            ),
          ),
          // Roles list
          Expanded(
            child: _isLoading
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
                              _searchQuery.isEmpty
                                  ? 'No roles found'
                                  : 'No roles match your search',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                            if (_searchQuery.isEmpty) ...[
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: () => _showAddRoleDialog(),
                                icon: const Icon(Icons.add),
                                label: const Text('Create Role'),
                              ),
                            ],
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
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddRoleDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Create Role'),
      ),
    );
  }
}
