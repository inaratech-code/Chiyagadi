import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../providers/unified_database_provider.dart';
import '../../models/category.dart';
import '../../models/product.dart';
import '../../utils/theme.dart';
import '../../utils/chiyagaadi_menu_seed.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io' as io;

class MenuScreen extends StatefulWidget {
  final bool hideAppBar;
  const MenuScreen({super.key, this.hideAppBar = false});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  List<Category> _categories = [];
  List<Product> _products = [];
  bool _isLoading = true;
  String _searchQuery = '';

  String _normalizeNameKey(String s) {
    return s.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _defaultMenuImageForName(String name) {
    return chiyagaadiImageAssetForName(name);
  }

  dynamic _categoryIdForName(String categoryName) {
    final target = _normalizeNameKey(categoryName);
    for (final c in _categories) {
      if (_normalizeNameKey(c.name) == target) {
        return _getCategoryIdentifier(c);
      }
    }
    return null;
  }

  Color _categoryColorForName(String categoryName) {
    final key = _normalizeNameKey(categoryName);
    if (key == _normalizeNameKey('Smokes')) return const Color(0xFF424242);
    if (key == _normalizeNameKey('Drinks')) return const Color(0xFF1976D2);
    // default accent for other categories
    return AppTheme.logoPrimary;
  }

  Widget _buildProductImage(String? imageUrl, String name) {
    final effectiveUrl =
        (imageUrl == null || imageUrl.trim().isEmpty) ? _defaultMenuImageForName(name) : imageUrl.trim();

    Widget fallback() => const Icon(Icons.image, size: 40, color: Colors.grey);

    if (effectiveUrl.startsWith('http')) {
      return Image.network(
        effectiveUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback(),
      );
    }

    if (effectiveUrl.startsWith('assets/')) {
      return Image.asset(
        effectiveUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback(),
      );
    }

    // Web: XFile from ImagePicker returns a blob/object URL which can be loaded via network.
    if (kIsWeb) {
      return Image.network(
        effectiveUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => fallback(),
      );
    }

    return Image.file(
      io.File(effectiveUrl),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => fallback(),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();

      final categoryMaps = await dbProvider.query(
        'categories',
        orderBy: 'display_order ASC',
      );
      _categories = categoryMaps.map((map) => Category.fromMap(map)).toList();

      final productMaps = await dbProvider.query(
        'products',
        where:
            'is_sellable = ? OR (is_sellable IS NULL OR is_sellable = 1)', // Default to sellable for backward compatibility
        whereArgs: [1],
      );
      _products = productMaps.map((map) => Product.fromMap(map)).toList();
    } catch (e) {
      debugPrint('Error loading menu data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  List<Product> get _filteredProducts {
    if (_searchQuery.isEmpty) {
      return _products;
    }
    return _products
        .where((p) =>
            p.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            (p.description != null &&
                p.description!
                    .toLowerCase()
                    .contains(_searchQuery.toLowerCase())))
        .toList();
  }

  // Group products by category
  Map<Category, List<Product>> get _productsByCategory {
    final Map<String, Category> categoryMap = {};
    final Map<String, List<Product>> grouped = {};

    // Create a map of category IDs to Category objects
    for (final cat in _categories) {
      final catId = _getCategoryIdentifier(cat);
      if (catId != null) {
        categoryMap[catId.toString()] = cat;
      }
    }

    // Create "Uncategorized" category
    final uncategorized = Category(
      name: 'Uncategorized',
      displayOrder: 9999,
      isActive: true,
      isLocked: false,
      createdAt: 0,
      updatedAt: 0,
    );

    // Group products by category
    for (final product in _filteredProducts) {
      String categoryKey = 'uncategorized';

      if (product.categoryId != null) {
        final catIdStr = product.categoryId.toString();
        if (categoryMap.containsKey(catIdStr)) {
          categoryKey = catIdStr;
        }
      }

      if (!grouped.containsKey(categoryKey)) {
        grouped[categoryKey] = [];
      }
      grouped[categoryKey]!.add(product);
    }

    // Convert to Map<Category, List<Product>> and sort by display order
    final result = <Category, List<Product>>{};
    for (final entry in grouped.entries) {
      Category cat;
      if (entry.key == 'uncategorized') {
        cat = uncategorized;
      } else {
        cat = categoryMap[entry.key]!;
      }
      result[cat] = entry.value;
    }

    // Sort categories by display order
    final sortedKeys = result.keys.toList()
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

    final sortedMap = <Category, List<Product>>{};
    for (final cat in sortedKeys) {
      sortedMap[cat] = result[cat]!;
    }

    return sortedMap;
  }

  // Helper method to get category identifier (int for SQLite, String for Firestore)
  dynamic _getCategoryIdentifier(Category category) {
    if (kIsWeb) {
      return category.documentId ?? category.id;
    }
    return category.id;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.hideAppBar
          ? null
          : AppBar(
              elevation: 0,
              title: const Text(
                'Menu Management',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.category),
                  onPressed: () => _showAddCategoryDialog(),
                  tooltip: 'Add Category',
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadData,
                  tooltip: 'Refresh',
                ),
              ],
            ),
      body: Column(
        children: [
          // Category Section
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.logoLight.withOpacity(0.22),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.1),
                  spreadRadius: 1,
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
              border: Border(
                bottom: BorderSide(
                  color: AppTheme.logoSecondary.withOpacity(0.25),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.category, color: AppTheme.logoPrimary, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Categories',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _showAddCategoryDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Category'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.logoPrimary,
                  ),
                ),
              ],
            ),
          ),
          // Search Bar
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.92),
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
                hintText: 'Search menu items...',
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
                  borderSide: BorderSide(
                      color: Theme.of(context).primaryColor, width: 2),
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

          // Menu Items List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredProducts.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.restaurant_menu,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'No menu items found'
                                  : 'No items match your search',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 16,
                              ),
                            ),
                            if (_searchQuery.isEmpty) ...[
                              const SizedBox(height: 8),
                              ElevatedButton.icon(
                                onPressed: () => _showAddProductDialog(),
                                icon: const Icon(Icons.add),
                                label: const Text('Add Menu Item'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor:
                                      Theme.of(context).primaryColor,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        child: _productsByCategory.isEmpty
                            ? const SizedBox.shrink()
                            : ListView.builder(
                                padding: const EdgeInsets.all(8),
                                itemCount: _productsByCategory.length,
                                itemBuilder: (context, categoryIndex) {
                                  final category = _productsByCategory.keys
                                      .elementAt(categoryIndex);
                                  final categoryProducts =
                                      _productsByCategory[category]!;

                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Category Heading
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 10),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 5),
                                              decoration: BoxDecoration(
                                                color: AppTheme.logoPrimary
                                                    .withOpacity(0.1),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: AppTheme.logoPrimary,
                                                  width: 1,
                                                ),
                                              ),
                                              child: Text(
                                                category.name.toUpperCase(),
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppTheme.logoPrimary,
                                                  letterSpacing: 0.5,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              '(${categoryProducts.length} items)',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey[600],
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Products Grid for this category
                                      GridView.builder(
                                        shrinkWrap: true,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8),
                                        gridDelegate:
                                            SliverGridDelegateWithFixedCrossAxisCount(
                                          crossAxisCount: () {
                                            final w =
                                                MediaQuery.of(context).size.width;
                                            // Smaller, cleaner boxes: increase columns on wide screens.
                                            // - phones: 2-3
                                            // - tablets: 4-5
                                            // - desktop: up to 8
                                            return (w / 150)
                                                .floor()
                                                .clamp(2, 8);
                                          }(),
                                          childAspectRatio: 0.86,
                                          crossAxisSpacing: 6,
                                          mainAxisSpacing: 6,
                                        ),
                                        itemCount: categoryProducts.length,
                                        itemBuilder: (context, productIndex) {
                                          final product =
                                              categoryProducts[productIndex];
                                          return _buildProductCard(product);
                                        },
                                      ),
                                      const SizedBox(height: 16),
                                    ],
                                  );
                                },
                              ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddProductDialog(),
        backgroundColor: Theme.of(context).primaryColor,
        icon: const Icon(Icons.add),
        label: const Text('Add Item'),
      ),
    );
  }

  Widget _buildProductCard(Product product) {
    final category = _categories.firstWhere(
      (c) {
        final catId = _getCategoryIdentifier(c);
        // Handle both int and String comparisons
        if (catId is int && product.categoryId is int) {
          return catId == product.categoryId;
        } else if (catId is String && product.categoryId is String) {
          return catId == product.categoryId;
        }
        // Fallback: try converting
        return catId.toString() == product.categoryId.toString();
      },
      orElse: () => Category(
        name: 'Unknown',
        createdAt: 0,
        updatedAt: 0,
      ),
    );

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _showEditProductDialog(product),
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            SizedBox(
              height: 72,
              width: double.infinity,
              child: DecoratedBox(
                decoration: BoxDecoration(color: Colors.grey[200]),
                child: _buildProductImage(product.imageUrl, product.name),
              ),
            ),

            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Single indicator (category color only)
                        Tooltip(
                          message: category.name,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: _categoryColorForName(category.name),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        if (!product.isActive) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey[700],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'OFF',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      product.name,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            NumberFormat.currency(symbol: 'NPR ')
                                .format(product.price),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.logoPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool?> _showAddCategoryDialog() async {
    final nameController = TextEditingController();
    bool isActive = true;
    String? categoryName;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(
                Icons.category,
                color: AppTheme.logoPrimary,
                size: 28,
              ),
              const SizedBox(width: 12),
              const Text(
                'Add Category',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'You need to add a category before adding products.',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: 'Category Name',
                    hintText: 'e.g., Beverages, Food, Snacks',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.label),
                    focusedBorder: OutlineInputBorder(
                      borderSide:
                          BorderSide(color: AppTheme.logoPrimary, width: 2),
                    ),
                  ),
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
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
              onPressed: () => Navigator.pop(context, null),
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Please enter a category name'),
                      backgroundColor: AppTheme.errorColor,
                    ),
                  );
                  return;
                }
                Navigator.pop(context, {
                  'name': nameController.text.trim(),
                  'isActive': isActive,
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.logoPrimary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Add Category'),
            ),
          ],
        ),
      ),
    );

    if (result != null && result['name'] != null) {
      try {
        final dbProvider =
            Provider.of<UnifiedDatabaseProvider>(context, listen: false);
        final now = DateTime.now().millisecondsSinceEpoch;
        categoryName = result['name'] as String;
        final categoryIsActive = result['isActive'] as bool;

        // Get the max display_order to add new category at the end
        final existingCategories = await dbProvider.query('categories');
        final normalizedNew = _normalizeNameKey(categoryName);
        final isDuplicate = existingCategories.any((c) {
          final existingName = (c['name'] as String?) ?? '';
          return _normalizeNameKey(existingName) == normalizedNew;
        });
        if (isDuplicate) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Category "$categoryName" already exists'),
                backgroundColor: AppTheme.errorColor,
              ),
            );
          }
          return false;
        }

        final maxOrder = existingCategories.isEmpty
            ? 0
            : (existingCategories
                    .map((c) => c['display_order'] as int? ?? 0)
                    .reduce((a, b) => a > b ? a : b) +
                1);

        await dbProvider.insert('categories', {
          'name': categoryName,
          'display_order': maxOrder,
          'is_active': categoryIsActive ? 1 : 0,
          'is_locked': 0,
          'created_at': now,
          'updated_at': now,
        });

        await _loadData(); // Reload data to show new category

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Category "$categoryName" added successfully'),
              backgroundColor: AppTheme.successColor,
            ),
          );
        }
        return true;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error adding category: $e'),
              backgroundColor: AppTheme.errorColor,
            ),
          );
        }
        return false;
      }
    }
    return false;
  }

  Future<void> _showAddProductDialog() async {
    if (_categories.isEmpty) {
      // Show dialog to add a category first
      final categoryAdded = await _showAddCategoryDialog();
      if (categoryAdded == true) {
        // Reload categories and then show add product dialog
        await _loadData();
        // Retry showing add product dialog if categories are now available
        if (_categories.isNotEmpty) {
          await _showAddProductDialog();
        }
      }
      return;
    }

    final nameController = TextEditingController();
    final descController = TextEditingController();
    final priceController = TextEditingController();
    final imageUrlController = TextEditingController();
    dynamic selectedCategoryId = _getCategoryIdentifier(_categories.first);
    bool isVeg = true;
    bool isActive = true;
    XFile? selectedImageFile; // Use XFile which works on both platforms

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.95,
            constraints: const BoxConstraints(maxWidth: 700, maxHeight: 800),
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Add Menu Item',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Title
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Title *',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Price and Category Row
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: priceController,
                          decoration: const InputDecoration(
                            labelText: 'Price (NPR) *',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<dynamic>(
                          value: selectedCategoryId,
                          decoration: const InputDecoration(
                            labelText: 'Category *',
                            border: OutlineInputBorder(),
                          ),
                          items: _categories.map((cat) {
                            final catId = _getCategoryIdentifier(cat);
                            return DropdownMenuItem(
                              value: catId,
                              child: Text(cat.name),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setDialogState(() => selectedCategoryId = value);
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Image Upload Section
                  Text(
                    'Product Image',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 150,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[300]!),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: selectedImageFile != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: kIsWeb
                                      ? Image.network(
                                          selectedImageFile!.path,
                                          fit: BoxFit.cover,
                                        )
                                      : Image.file(
                                          io.File(selectedImageFile!.path),
                                          fit: BoxFit.cover,
                                        ),
                                )
                              : imageUrlController.text.isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Image.network(
                                        imageUrlController.text,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                          return const Center(
                                            child: Icon(Icons.image,
                                                size: 48, color: Colors.grey),
                                          );
                                        },
                                      ),
                                    )
                                  : const Center(
                                      child: Icon(Icons.image,
                                          size: 48, color: Colors.grey),
                                    ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        children: [
                          ElevatedButton.icon(
                            onPressed: () async {
                              final picker = ImagePicker();
                              final pickedFile = await picker.pickImage(
                                source: ImageSource.gallery,
                                maxWidth: 800,
                                maxHeight: 800,
                                imageQuality: 85,
                              );
                              if (pickedFile != null) {
                                setDialogState(() {
                                  selectedImageFile = pickedFile;
                                  imageUrlController.clear();
                                });
                              }
                            },
                            icon: const Icon(Icons.photo_library),
                            label: const Text('Gallery'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: () async {
                              final picker = ImagePicker();
                              final pickedFile = await picker.pickImage(
                                source: ImageSource.camera,
                                maxWidth: 800,
                                maxHeight: 800,
                                imageQuality: 85,
                              );
                              if (pickedFile != null) {
                                setDialogState(() {
                                  selectedImageFile = pickedFile;
                                  imageUrlController.clear();
                                });
                              }
                            },
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Camera'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                            ),
                          ),
                          if (selectedImageFile != null ||
                              imageUrlController.text.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () {
                                setDialogState(() {
                                  selectedImageFile = null;
                                  imageUrlController.clear();
                                });
                              },
                              icon: const Icon(Icons.delete),
                              label: const Text('Remove'),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: imageUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Or enter Image URL',
                      hintText: 'https://...',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      if (value.isNotEmpty) {
                        setDialogState(() {
                          selectedImageFile = null;
                        });
                      }
                    },
                  ),

                  const SizedBox(height: 16),

                  // Description
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),

                  const SizedBox(height: 16),

                  // Checkboxes
                  Row(
                    children: [
                      Checkbox(
                        value: isVeg,
                        onChanged: (value) {
                          setDialogState(() => isVeg = value ?? true);
                        },
                      ),
                      const Text('Vegetarian'),
                      const SizedBox(width: 24),
                      Checkbox(
                        value: isActive,
                        onChanged: (value) {
                          setDialogState(() => isActive = value ?? true);
                        },
                      ),
                      const Text('Available'),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Quick category toggles (Smokes / Drinks) – checkbox + color only
                  Row(
                    children: [
                      Tooltip(
                        message: 'Smokes',
                        child: Row(
                          children: [
                            Checkbox(
                              value: selectedCategoryId?.toString() ==
                                  _categoryIdForName('Smokes')?.toString(),
                              onChanged: (v) {
                                final smokesId = _categoryIdForName('Smokes');
                                if (smokesId == null) return;
                                setDialogState(() {
                                  if (v == true) {
                                    selectedCategoryId = smokesId;
                                  } else {
                                    selectedCategoryId =
                                        _getCategoryIdentifier(_categories.first);
                                  }
                                });
                              },
                            ),
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: _categoryColorForName('Smokes'),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'SM',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey[700],
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 18),
                      Tooltip(
                        message: 'Drinks',
                        child: Row(
                          children: [
                            Checkbox(
                              value: selectedCategoryId?.toString() ==
                                  _categoryIdForName('Drinks')?.toString(),
                              onChanged: (v) {
                                final drinksId = _categoryIdForName('Drinks');
                                if (drinksId == null) return;
                                setDialogState(() {
                                  if (v == true) {
                                    selectedCategoryId = drinksId;
                                  } else {
                                    selectedCategoryId =
                                        _getCategoryIdentifier(_categories.first);
                                  }
                                });
                              },
                            ),
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: _categoryColorForName('Drinks'),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'DR',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey[700],
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Buttons
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
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32, vertical: 12),
                        ),
                        child: const Text('Add Item'),
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

    if (result == true &&
        nameController.text.isNotEmpty &&
        priceController.text.isNotEmpty &&
        selectedCategoryId != null) {
      try {
        final now = DateTime.now().millisecondsSinceEpoch;

        // Disallow duplicate menu item names (case-insensitive).
        final newName = nameController.text.trim();
        final normalizedNew = _normalizeNameKey(newName);
        final isDuplicate = _products.any((p) => _normalizeNameKey(p.name) == normalizedNew);
        if (isDuplicate) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Menu item "$newName" already exists'),
                backgroundColor: AppTheme.errorColor,
              ),
            );
          }
          return;
        }

        String? finalImageUrl = imageUrlController.text.trim().isEmpty
            ? null
            : imageUrlController.text.trim();

        // If image was uploaded, copy it to app directory and use local path
        if (selectedImageFile != null && !kIsWeb) {
          try {
            final appDir = await getApplicationDocumentsDirectory();
            final imageDir = io.Directory('${appDir.path}/product_images');
            if (!await imageDir.exists()) {
              await imageDir.create(recursive: true);
            }
            final fileName =
                '${now}_${nameController.text.trim().replaceAll(' ', '_')}.jpg';
            final savedImage = await io.File(selectedImageFile!.path)
                .copy('${imageDir.path}/$fileName');
            finalImageUrl = savedImage.path;
          } catch (e) {
            debugPrint('Error saving image: $e');
          }
        }

        // Auto-assign image by name if none provided.
        finalImageUrl ??= _defaultMenuImageForName(newName);

        final dbProvider =
            Provider.of<UnifiedDatabaseProvider>(context, listen: false);
        await dbProvider.insert('products', {
          'category_id': selectedCategoryId,
          'name': newName,
          'description': descController.text.trim().isEmpty
              ? null
              : descController.text.trim(),
          'price': double.parse(priceController.text),
          'cost': 0,
          'image_url': finalImageUrl,
          'is_veg': isVeg ? 1 : 0,
          'is_active': isActive ? 1 : 0,
          'is_purchasable': 0, // Menu items are not purchasable by default
          'is_sellable': 1, // Menu items are sellable
          'created_at': now,
          'updated_at': now,
        });
        await _loadData(); // Await to ensure data is loaded
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Product added successfully'),
              backgroundColor: AppTheme.successColor,
            ),
          );
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

  Future<void> _showEditProductDialog(Product product) async {
    final nameController = TextEditingController(text: product.name);
    final descController =
        TextEditingController(text: product.description ?? '');
    final priceController =
        TextEditingController(text: product.price.toString());
    final imageUrlController =
        TextEditingController(text: product.imageUrl ?? '');
    // Find the category that matches this product's categoryId
    final matchingCategory = _categories.firstWhere(
      (c) {
        final catId = _getCategoryIdentifier(c);
        return catId.toString() == product.categoryId.toString();
      },
      orElse: () => _categories.isNotEmpty
          ? _categories.first
          : Category(
              name: 'Unknown',
              createdAt: 0,
              updatedAt: 0,
            ),
    );
    dynamic selectedCategoryId = _getCategoryIdentifier(matchingCategory);
    bool isVeg = product.isVeg;
    bool isActive = product.isActive;
    XFile? selectedImageFile; // Use XFile which works on both platforms

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.95,
            constraints: const BoxConstraints(maxWidth: 700, maxHeight: 800),
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Edit Menu Item',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Title
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Title *',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Price and Category Row
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: priceController,
                          decoration: const InputDecoration(
                            labelText: 'Price (NPR) *',
                            border: OutlineInputBorder(),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<dynamic>(
                          value: selectedCategoryId,
                          decoration: const InputDecoration(
                            labelText: 'Category *',
                            border: OutlineInputBorder(),
                          ),
                          items: _categories.map((cat) {
                            final catId = _getCategoryIdentifier(cat);
                            return DropdownMenuItem(
                              value: catId,
                              child: Text(cat.name),
                            );
                          }).toList(),
                          onChanged: (value) {
                            setDialogState(() => selectedCategoryId = value);
                          },
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Image Upload Section
                  Text(
                    'Product Image',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 150,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey[300]!),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: selectedImageFile != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: kIsWeb
                                      ? Image.network(
                                          selectedImageFile!.path,
                                          fit: BoxFit.cover,
                                        )
                                      : Image.file(
                                          io.File(selectedImageFile!.path),
                                          fit: BoxFit.cover,
                                        ),
                                )
                              : imageUrlController.text.isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: imageUrlController.text
                                              .startsWith('http')
                                          ? Image.network(
                                              imageUrlController.text,
                                              fit: BoxFit.cover,
                                              errorBuilder:
                                                  (context, error, stackTrace) {
                                                return const Center(
                                                  child: Icon(Icons.image,
                                                      size: 48,
                                                      color: Colors.grey),
                                                );
                                              },
                                            )
                                          : kIsWeb
                                              ? Image.network(
                                                  imageUrlController.text,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error,
                                                      stackTrace) {
                                                    return const Center(
                                                      child: Icon(Icons.image,
                                                          size: 48,
                                                          color: Colors.grey),
                                                    );
                                                  },
                                                )
                                              : Image.file(
                                                  io.File(
                                                      imageUrlController.text),
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error,
                                                      stackTrace) {
                                                    return const Center(
                                                      child: Icon(Icons.image,
                                                          size: 48,
                                                          color: Colors.grey),
                                                    );
                                                  },
                                                ),
                                    )
                                  : const Center(
                                      child: Icon(Icons.image,
                                          size: 48, color: Colors.grey),
                                    ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        children: [
                          ElevatedButton.icon(
                            onPressed: () async {
                              final picker = ImagePicker();
                              final pickedFile = await picker.pickImage(
                                source: ImageSource.gallery,
                                maxWidth: 800,
                                maxHeight: 800,
                                imageQuality: 85,
                              );
                              if (pickedFile != null) {
                                setDialogState(() {
                                  selectedImageFile = pickedFile;
                                  imageUrlController.clear();
                                });
                              }
                            },
                            icon: const Icon(Icons.photo_library),
                            label: const Text('Gallery'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ElevatedButton.icon(
                            onPressed: () async {
                              final picker = ImagePicker();
                              final pickedFile = await picker.pickImage(
                                source: ImageSource.camera,
                                maxWidth: 800,
                                maxHeight: 800,
                                imageQuality: 85,
                              );
                              if (pickedFile != null) {
                                setDialogState(() {
                                  selectedImageFile = pickedFile;
                                  imageUrlController.clear();
                                });
                              }
                            },
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Camera'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                            ),
                          ),
                          if (selectedImageFile != null ||
                              imageUrlController.text.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            TextButton.icon(
                              onPressed: () {
                                setDialogState(() {
                                  selectedImageFile = null;
                                  imageUrlController.clear();
                                });
                              },
                              icon: const Icon(Icons.delete),
                              label: const Text('Remove'),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: imageUrlController,
                    decoration: const InputDecoration(
                      labelText: 'Or enter Image URL',
                      hintText: 'https://...',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) {
                      if (value.isNotEmpty) {
                        setDialogState(() {
                          selectedImageFile = null;
                        });
                      }
                    },
                  ),

                  const SizedBox(height: 16),

                  // Description
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),

                  const SizedBox(height: 12),

                  // Checkboxes
                  Row(
                    children: [
                      Checkbox(
                        value: isVeg,
                        onChanged: (value) {
                          setDialogState(() => isVeg = value ?? true);
                        },
                      ),
                      const Text('Vegetarian'),
                      const SizedBox(width: 16),
                      Checkbox(
                        value: isActive,
                        onChanged: (value) {
                          setDialogState(() => isActive = value ?? true);
                        },
                      ),
                      const Text('Available'),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Quick category toggles (Smokes / Drinks) – checkbox + color only
                  Row(
                    children: [
                      Tooltip(
                        message: 'Smokes',
                        child: Row(
                          children: [
                            Checkbox(
                              value: selectedCategoryId?.toString() ==
                                  _categoryIdForName('Smokes')?.toString(),
                              onChanged: (v) {
                                final smokesId = _categoryIdForName('Smokes');
                                if (smokesId == null) return;
                                setDialogState(() {
                                  if (v == true) {
                                    selectedCategoryId = smokesId;
                                  } else {
                                    selectedCategoryId =
                                        _getCategoryIdentifier(_categories.first);
                                  }
                                });
                              },
                            ),
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: _categoryColorForName('Smokes'),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'SM',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey[700],
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 18),
                      Tooltip(
                        message: 'Drinks',
                        child: Row(
                          children: [
                            Checkbox(
                              value: selectedCategoryId?.toString() ==
                                  _categoryIdForName('Drinks')?.toString(),
                              onChanged: (v) {
                                final drinksId = _categoryIdForName('Drinks');
                                if (drinksId == null) return;
                                setDialogState(() {
                                  if (v == true) {
                                    selectedCategoryId = drinksId;
                                  } else {
                                    selectedCategoryId =
                                        _getCategoryIdentifier(_categories.first);
                                  }
                                });
                              },
                            ),
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: _categoryColorForName('Drinks'),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'DR',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey[700],
                                letterSpacing: 0.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Buttons
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
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 32, vertical: 12),
                        ),
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

    if (result == true &&
        nameController.text.isNotEmpty &&
        priceController.text.isNotEmpty &&
        selectedCategoryId != null &&
        (kIsWeb ? product.documentId != null : product.id != null)) {
      try {
        final newName = nameController.text.trim();

        // Disallow duplicate menu item names (case-insensitive), excluding self.
        final normalizedNew = _normalizeNameKey(newName);
        final isDuplicate = _products.any((p) {
          final sameRecord = kIsWeb
              ? (p.documentId != null && p.documentId == product.documentId)
              : (p.id != null && p.id == product.id);
          if (sameRecord) return false;
          return _normalizeNameKey(p.name) == normalizedNew;
        });
        if (isDuplicate) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Menu item "$newName" already exists'),
                backgroundColor: AppTheme.errorColor,
              ),
            );
          }
          return;
        }

        String? finalImageUrl = imageUrlController.text.trim().isEmpty
            ? null
            : imageUrlController.text.trim();

        // If image was uploaded, copy it to app directory and use local path
        if (selectedImageFile != null && !kIsWeb) {
          try {
            final appDir = await getApplicationDocumentsDirectory();
            final imageDir = io.Directory('${appDir.path}/product_images');
            if (!await imageDir.exists()) {
              await imageDir.create(recursive: true);
            }
            final now = DateTime.now().millisecondsSinceEpoch;
            final fileName =
                '${now}_${nameController.text.trim().replaceAll(' ', '_')}.jpg';
            final savedImage = await io.File(selectedImageFile!.path)
                .copy('${imageDir.path}/$fileName');
            finalImageUrl = savedImage.path;
          } catch (e) {
            debugPrint('Error saving image: $e');
          }
        }

        final dbProvider =
            Provider.of<UnifiedDatabaseProvider>(context, listen: false);

        // Auto-assign image by name if none provided.
        finalImageUrl ??= _defaultMenuImageForName(newName);

        await dbProvider.update(
          'products',
          values: {
            'category_id': selectedCategoryId,
            'name': newName,
            'description': descController.text.trim().isEmpty
                ? null
                : descController.text.trim(),
            'price': double.parse(priceController.text),
            'image_url': finalImageUrl,
            'is_veg': isVeg ? 1 : 0,
            'is_active': isActive ? 1 : 0,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          where: kIsWeb ? 'documentId = ?' : 'id = ?',
          whereArgs: [kIsWeb ? product.documentId : product.id],
        );
        await _loadData(); // Await to ensure data is loaded
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Product updated'),
              backgroundColor: AppTheme.successColor,
            ),
          );
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
}
