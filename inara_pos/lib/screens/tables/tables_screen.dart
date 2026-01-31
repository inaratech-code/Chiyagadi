import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import '../../providers/unified_database_provider.dart';
import '../../models/table.dart';
import '../../widgets/responsive_wrapper.dart';
import '../../utils/theme.dart';

class TablesScreen extends StatefulWidget {
  final bool hideAppBar;
  const TablesScreen({super.key, this.hideAppBar = false});

  @override
  State<TablesScreen> createState() => _TablesScreenState();
}

class _TablesScreenState extends State<TablesScreen> {
  List<CafeTable> _tables = [];
  bool _isLoading = false;
  bool _isCreatingTable = false; // Prevent duplicate submissions

  @override
  void initState() {
    super.initState();
    // Load tables after first frame to ensure context is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTables();
    });
  }

  Future<void> _loadTables() async {
    if (!mounted) return;
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      // Ensure database is initialized
      await dbProvider.init();
      final maps =
          await dbProvider.query('tables', orderBy: 'table_number ASC');
      if (mounted) {
        setState(() {
          _tables = maps.map((map) => CafeTable.fromMap(map)).toList();
        });
      }
    } catch (e, stackTrace) {
      debugPrint('Error loading tables: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading tables: ${e.toString()}'),
            backgroundColor: AppTheme.errorColor,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.hideAppBar
          ? null
          : AppBar(
              title: const Text('Table Management'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadTables,
                  tooltip: 'Refresh',
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => _showAddTableDialog(),
                  tooltip: 'Add Table',
                ),
              ],
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _tables.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.table_restaurant,
                          size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('No tables found',
                          style:
                              TextStyle(color: Colors.grey[600], fontSize: 16)),
                      const SizedBox(height: 8),
                      ElevatedButton.icon(
                        onPressed: () => _showAddTableDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text('Add Table'),
                      ),
                    ],
                  ),
                )
              : ResponsiveWrapper(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Responsive grid: 2 columns on mobile, 3 on tablet, 4+ on desktop
                      final crossAxisCount = kIsWeb
                          ? (constraints.maxWidth > 1200
                              ? 5
                              : constraints.maxWidth > 800
                                  ? 4
                                  : 3)
                          : (constraints.maxWidth > 600 ? 3 : 2);

                      return GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: 1.1,
                        ),
                        itemCount: _tables.length,
                        itemBuilder: (context, index) {
                          final table = _tables[index];
                          final isOccupied = table.status == 'occupied';
                          return MouseRegion(
                            cursor: kIsWeb
                                ? SystemMouseCursors.click
                                : MouseCursor.defer,
                            child: Card(
                              elevation: isOccupied ? 4 : 2,
                              color: isOccupied
                                  ? AppTheme.errorColor.withOpacity(0.1)
                                  : AppTheme.successColor.withOpacity(0.1),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: isOccupied
                                      ? AppTheme.errorColor
                                      : AppTheme.successColor,
                                  width: 2,
                                ),
                              ),
                              child: InkWell(
                                onTap: () => _showTableDetails(table),
                                borderRadius: BorderRadius.circular(12),
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: isOccupied
                                              ? AppTheme.errorColor
                                                  .withOpacity(0.2)
                                              : AppTheme.successColor
                                                  .withOpacity(0.2),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          Icons.table_restaurant,
                                          size: 36,
                                          color: isOccupied
                                              ? AppTheme.errorColor
                                              : AppTheme.successColor,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Table ${table.tableNumber}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: isOccupied
                                              ? AppTheme.errorColor
                                              : AppTheme.successColor,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      if (table.positionLabel != null &&
                                          table.positionLabel!.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          table.positionLabel!,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey[600],
                                            fontStyle: FontStyle.italic,
                                          ),
                                          textAlign: TextAlign.center,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                      const SizedBox(height: 6),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.people,
                                            size: 12,
                                            color: Colors.grey[600],
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${table.capacity}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey[700],
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: isOccupied
                                              ? AppTheme.errorColor
                                                  .withOpacity(0.3)
                                              : AppTheme.successColor
                                                  .withOpacity(0.3),
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          isOccupied ? 'OCCUPIED' : 'AVAILABLE',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: isOccupied
                                                ? AppTheme.errorColor
                                                : AppTheme.successColor,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
      floatingActionButton: _tables.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => _showAddTableDialog(),
              backgroundColor: AppTheme.logoPrimary,
              icon: const Icon(Icons.add),
              label: const Text('Add Table'),
            )
          : null,
    );
  }

  Future<void> _showAddTableDialog() async {
    final numberController = TextEditingController();
    final capacityController = TextEditingController(text: '4');
    final rowController = TextEditingController();
    final columnController = TextEditingController();
    final positionLabelController = TextEditingController();
    final notesController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            constraints: const BoxConstraints(maxWidth: 500),
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Add Table',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: numberController,
                    decoration: const InputDecoration(
                      labelText: 'Table Number *',
                      border: OutlineInputBorder(),
                    ),
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: capacityController,
                          decoration: const InputDecoration(
                            labelText: 'Capacity *',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: positionLabelController,
                          decoration: const InputDecoration(
                            labelText: 'Position Label',
                            hintText: 'e.g., Window, Corner',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: rowController,
                          decoration: const InputDecoration(
                            labelText: 'Row Position',
                            hintText: 'Optional',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: columnController,
                          decoration: const InputDecoration(
                            labelText: 'Column Position',
                            hintText: 'Optional',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesController,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: _isCreatingTable
                            ? null
                            : () => Navigator.pop(context, true),
                        child: _isCreatingTable
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Add'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (result == true) {
      // Validate inputs
      if (numberController.text.trim().isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please enter a table number'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
        return;
      }

      final capacityText = capacityController.text.trim();
      if (capacityText.isEmpty) {
        setState(() => _isCreatingTable = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please enter table capacity'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
        return;
      }

      final capacity = int.tryParse(capacityText);
      if (capacity == null || capacity <= 0) {
        setState(() => _isCreatingTable = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content:
                  Text('Please enter a valid capacity (number greater than 0)'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
        return;
      }

      if (!mounted) return;

      try {
        final dbProvider =
            Provider.of<UnifiedDatabaseProvider>(context, listen: false);
        // Ensure database is initialized
        await dbProvider.init();

        // Check if table number already exists
        final existing = await dbProvider.query(
          'tables',
          where: 'table_number = ?',
          whereArgs: [numberController.text.trim()],
        );

        if (existing.isNotEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Table number already exists'),
                backgroundColor: AppTheme.warningColor,
              ),
            );
          }
          numberController.dispose();
          capacityController.dispose();
          rowController.dispose();
          columnController.dispose();
          positionLabelController.dispose();
          notesController.dispose();
          return;
        }

        final now = DateTime.now().millisecondsSinceEpoch;
        await dbProvider.insert('tables', {
          'table_number': numberController.text.trim(),
          'capacity': capacity,
          'status': 'available',
          'row_position': rowController.text.trim().isEmpty
              ? null
              : int.tryParse(rowController.text.trim()),
          'column_position': columnController.text.trim().isEmpty
              ? null
              : int.tryParse(columnController.text.trim()),
          'position_label': positionLabelController.text.trim().isEmpty
              ? null
              : positionLabelController.text.trim(),
          'notes': notesController.text.trim().isEmpty
              ? null
              : notesController.text.trim(),
          'created_at': now,
          'updated_at': now,
        });

        // Dispose controllers
        numberController.dispose();
        capacityController.dispose();
        rowController.dispose();
        columnController.dispose();
        positionLabelController.dispose();
        notesController.dispose();

        if (mounted) {
          setState(() => _isCreatingTable = false);
          _loadTables();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Table added successfully'),
              backgroundColor: AppTheme.successColor,
            ),
          );
        }
      } catch (e) {
        debugPrint('Error adding table: $e');
        numberController.dispose();
        capacityController.dispose();
        rowController.dispose();
        columnController.dispose();
        positionLabelController.dispose();
        notesController.dispose();
        if (mounted) {
          setState(() => _isCreatingTable = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error adding table: ${e.toString()}'),
              backgroundColor: AppTheme.errorColor,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } else {
      // Dispose controllers if dialog was cancelled
      numberController.dispose();
      capacityController.dispose();
      rowController.dispose();
      columnController.dispose();
      positionLabelController.dispose();
      notesController.dispose();
    }
  }

  Future<void> _showTableDetails(CafeTable table) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(
              Icons.table_restaurant,
              color: table.status == 'occupied'
                  ? AppTheme.errorColor
                  : AppTheme.successColor,
            ),
            const SizedBox(width: 8),
            Text('Table ${table.tableNumber}'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Status Section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: table.status == 'occupied'
                      ? AppTheme.errorColor.withOpacity(0.1)
                      : AppTheme.successColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: table.status == 'occupied'
                        ? AppTheme.errorColor
                        : AppTheme.successColor,
                    width: 2,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: table.status == 'occupied'
                            ? AppTheme.errorColor
                            : AppTheme.successColor,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        table.status == 'occupied'
                            ? Icons.event_busy
                            : Icons.event_available,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Status',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            table.status.toUpperCase(),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: table.status == 'occupied'
                                  ? AppTheme.errorColor
                                  : AppTheme.successColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Status Toggle Button
                    IconButton(
                      icon: Icon(
                        table.status == 'occupied'
                            ? Icons.check_circle_outline
                            : Icons.cancel_outlined,
                        color: table.status == 'occupied'
                            ? AppTheme.successColor
                            : AppTheme.errorColor,
                      ),
                      onPressed: () {
                        _toggleTableStatus(table);
                        Navigator.pop(context);
                      },
                      tooltip: table.status == 'occupied'
                          ? 'Mark as Available'
                          : 'Mark as Occupied',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _buildDetailRow('Capacity', '${table.capacity} seats'),
              if (table.positionLabel != null &&
                  table.positionLabel!.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildDetailRow('Position', table.positionLabel!),
              ],
              if (table.rowPosition != null ||
                  table.columnPosition != null) ...[
                const SizedBox(height: 8),
                _buildDetailRow(
                  'Location',
                  'Row: ${table.rowPosition ?? 'N/A'}, Col: ${table.columnPosition ?? 'N/A'}',
                ),
              ],
              if (table.notes != null && table.notes!.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildDetailRow('Notes', table.notes!),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _confirmDeleteTable(table);
            },
            style: TextButton.styleFrom(foregroundColor: AppTheme.errorColor),
            child: const Text('Delete'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showEditTableDialog(table);
            },
            child: const Text('Edit'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleTableStatus(CafeTable table) async {
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      final newStatus = table.status == 'occupied' ? 'available' : 'occupied';

      // For Firestore, use table_number; for SQLite, use id
      if (kIsWeb && table.documentId != null) {
        await dbProvider.update(
          'tables',
          values: {
            'status': newStatus,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'table_number = ?',
          whereArgs: [table.tableNumber],
        );
      } else {
        await dbProvider.update(
          'tables',
          values: {
            'status': newStatus,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: 'id = ?',
          whereArgs: [table.id],
        );
      }

      if (mounted) {
        _loadTables();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Table ${table.tableNumber} marked as ${newStatus.toUpperCase()}'),
            backgroundColor: newStatus == 'occupied'
                ? AppTheme.errorColor
                : AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error updating table status: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating table status: ${e.toString()}'),
            backgroundColor: AppTheme.errorColor,
          ),
        );
      }
    }
  }

  Widget _buildDetailRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            '$label:',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDeleteTable(CafeTable table) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Delete Table?'),
        content: Text(
            'Are you sure you want to delete Table ${table.tableNumber}? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style:
                ElevatedButton.styleFrom(backgroundColor: AppTheme.errorColor),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        final dbProvider =
            Provider.of<UnifiedDatabaseProvider>(context, listen: false);
        // For Firestore, use table_number; for SQLite, use id
        if (kIsWeb && table.documentId != null) {
          // Firestore: use documentId directly via table_number lookup
          await dbProvider.delete('tables',
              where: 'table_number = ?', whereArgs: [table.tableNumber]);
        } else {
          // SQLite: use integer id
          await dbProvider
              .delete('tables', where: 'id = ?', whereArgs: [table.id]);
        }

        if (mounted) {
          _loadTables();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Table ${table.tableNumber} deleted successfully'),
              backgroundColor: AppTheme.successColor,
            ),
          );
        }
      } catch (e) {
        debugPrint('Error deleting table: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting table: ${e.toString()}'),
              backgroundColor: AppTheme.errorColor,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    }
  }

  Future<void> _showEditTableDialog(CafeTable table) async {
    final numberController = TextEditingController(text: table.tableNumber);
    final capacityController =
        TextEditingController(text: table.capacity.toString());
    final rowController =
        TextEditingController(text: table.rowPosition?.toString() ?? '');
    final columnController =
        TextEditingController(text: table.columnPosition?.toString() ?? '');
    final positionLabelController =
        TextEditingController(text: table.positionLabel ?? '');
    final notesController = TextEditingController(text: table.notes ?? '');
    String status = table.status;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            constraints: const BoxConstraints(maxWidth: 500),
            padding: const EdgeInsets.all(20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Edit Table',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: numberController,
                    decoration: const InputDecoration(
                      labelText: 'Table Number *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: capacityController,
                          decoration: const InputDecoration(
                            labelText: 'Capacity *',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          value: status,
                          decoration: const InputDecoration(
                            labelText: 'Status *',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                                value: 'available', child: Text('Available')),
                            DropdownMenuItem(
                                value: 'occupied', child: Text('Occupied')),
                          ],
                          onChanged: (value) {
                            setDialogState(() => status = value!);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: rowController,
                          decoration: const InputDecoration(
                            labelText: 'Row Position',
                            hintText: 'Optional',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: columnController,
                          decoration: const InputDecoration(
                            labelText: 'Column Position',
                            hintText: 'Optional',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: positionLabelController,
                    decoration: const InputDecoration(
                      labelText: 'Position Label',
                      hintText: 'e.g., Window, Corner',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesController,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (result == true) {
      // Validate inputs
      if (numberController.text.trim().isEmpty) {
        numberController.dispose();
        capacityController.dispose();
        rowController.dispose();
        columnController.dispose();
        positionLabelController.dispose();
        notesController.dispose();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please enter a table number'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
        return;
      }

      final capacityText = capacityController.text.trim();
      final capacity = int.tryParse(capacityText);
      if (capacity == null || capacity <= 0) {
        numberController.dispose();
        capacityController.dispose();
        rowController.dispose();
        columnController.dispose();
        positionLabelController.dispose();
        notesController.dispose();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please enter a valid capacity'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
        return;
      }

      // Check if we have a valid identifier (id for SQLite or documentId for Firestore)
      if (table.id == null && table.documentId == null) {
        numberController.dispose();
        capacityController.dispose();
        rowController.dispose();
        columnController.dispose();
        positionLabelController.dispose();
        notesController.dispose();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cannot update table: Invalid table ID'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
        return;
      }

      if (!mounted) {
        numberController.dispose();
        capacityController.dispose();
        rowController.dispose();
        columnController.dispose();
        positionLabelController.dispose();
        notesController.dispose();
        return;
      }

      try {
        final dbProvider =
            Provider.of<UnifiedDatabaseProvider>(context, listen: false);
        // For Firestore, use table_number; for SQLite, use id
        if (kIsWeb && table.documentId != null) {
          // Firestore: use table_number to find the document
          await dbProvider.update(
            'tables',
            values: {
              'table_number': numberController.text.trim(),
              'capacity': capacity,
              'status': status,
              'row_position': rowController.text.trim().isEmpty
                  ? null
                  : int.tryParse(rowController.text.trim()),
              'column_position': columnController.text.trim().isEmpty
                  ? null
                  : int.tryParse(columnController.text.trim()),
              'position_label': positionLabelController.text.trim().isEmpty
                  ? null
                  : positionLabelController.text.trim(),
              'notes': notesController.text.trim().isEmpty
                  ? null
                  : notesController.text.trim(),
              'updated_at': DateTime.now().millisecondsSinceEpoch,
            },
            where: 'table_number = ?',
            whereArgs: [table.tableNumber],
          );
        } else {
          // SQLite: use integer id
          await dbProvider.update(
            'tables',
            values: {
              'table_number': numberController.text.trim(),
              'capacity': capacity,
              'status': status,
              'row_position': rowController.text.trim().isEmpty
                  ? null
                  : int.tryParse(rowController.text.trim()),
              'column_position': columnController.text.trim().isEmpty
                  ? null
                  : int.tryParse(columnController.text.trim()),
              'position_label': positionLabelController.text.trim().isEmpty
                  ? null
                  : positionLabelController.text.trim(),
              'notes': notesController.text.trim().isEmpty
                  ? null
                  : notesController.text.trim(),
              'updated_at': DateTime.now().millisecondsSinceEpoch,
            },
            where: 'id = ?',
            whereArgs: [table.id],
          );
        }

        // Dispose controllers
        numberController.dispose();
        capacityController.dispose();
        rowController.dispose();
        columnController.dispose();
        positionLabelController.dispose();
        notesController.dispose();

        if (mounted) {
          _loadTables();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Table updated successfully'),
              backgroundColor: AppTheme.successColor,
            ),
          );
        }
      } catch (e) {
        debugPrint('Error updating table: $e');
        numberController.dispose();
        capacityController.dispose();
        rowController.dispose();
        columnController.dispose();
        positionLabelController.dispose();
        notesController.dispose();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error updating table: ${e.toString()}'),
              backgroundColor: AppTheme.errorColor,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } else {
      // Dispose controllers if dialog was cancelled
      numberController.dispose();
      capacityController.dispose();
      rowController.dispose();
      columnController.dispose();
      positionLabelController.dispose();
      notesController.dispose();
    }
  }
}
