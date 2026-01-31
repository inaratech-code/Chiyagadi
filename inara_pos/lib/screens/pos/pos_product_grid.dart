import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/product.dart';
import '../../models/category.dart';
import '../../providers/unified_database_provider.dart';
import '../../utils/number_formatter.dart';

class POSProductGrid extends StatefulWidget {
  final Function(Product) onProductSelected;
  final String orderType;

  const POSProductGrid({
    super.key,
    required this.onProductSelected,
    required this.orderType,
  });

  @override
  State<POSProductGrid> createState() => _POSProductGridState();
}

class _POSProductGridState extends State<POSProductGrid> {
  List<Category> _categories = [];
  List<Product> _products = [];
  int? _selectedCategoryId;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // PERF: Let the widget render first.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    try {
      final dbProvider =
          Provider.of<UnifiedDatabaseProvider>(context, listen: false);
      await dbProvider.init();
      final categoryMaps = await dbProvider.query(
        'categories',
        where: 'is_active = ?',
        whereArgs: [1],
        orderBy: 'display_order ASC, name ASC',
      );
      _categories = categoryMaps.map((map) => Category.fromMap(map)).toList();

      // Default to the first category for a faster initial load.
      if (_categories.isNotEmpty && _selectedCategoryId == null) {
        _selectedCategoryId = _categories.first.id;
      }
      await _loadProducts();
    } catch (e) {
      debugPrint('Error loading data: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadProducts() async {
    final dbProvider =
        Provider.of<UnifiedDatabaseProvider>(context, listen: false);
    if (_selectedCategoryId == null) {
      final productMaps = await dbProvider.query(
        'products',
        where: 'is_active = ?',
        whereArgs: [1],
        orderBy: 'name ASC',
      );
      _products = productMaps.map((map) => Product.fromMap(map)).toList();
    } else {
      final productMaps = await dbProvider.query(
        'products',
        where: 'category_id = ? AND is_active = ?',
        whereArgs: [_selectedCategoryId, 1],
        orderBy: 'name ASC',
      );
      _products = productMaps.map((map) => Product.fromMap(map)).toList();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Category tabs - Improved design
        if (_categories.isNotEmpty)
          Container(
            height: 60,
            decoration: BoxDecoration(
              color: const Color(0xFF2D2D2D),
              border: Border(
                bottom: BorderSide(color: Colors.grey[800]!, width: 1),
              ),
            ),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final category = _categories[index];
                final isSelected = category.id == _selectedCategoryId;
                return Container(
                  margin: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedCategoryId = category.id;
                      });
                      _loadProducts();
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFFFFC107)
                            : Colors.grey[800],
                        borderRadius: BorderRadius.circular(20),
                        border: isSelected
                            ? Border.all(
                                color: const Color(0xFFFFC107), width: 2)
                            : null,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _getCategoryEmoji(category.name),
                            style: const TextStyle(fontSize: 18),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            category.name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color:
                                  isSelected ? Colors.white : Colors.grey[300],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

        // Product grid
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _products.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.restaurant_menu,
                            size: 64,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No products available',
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        childAspectRatio: 0.75,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: _products.length,
                      itemBuilder: (context, index) {
                        final product = _products[index];
                        return _buildProductCard(product);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildProductCard(Product product) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          widget.onProductSelected(product);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF2D2D2D),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.grey[700]!,
              width: 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Top section - Veg indicator
              if (!product.isVeg)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.2),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Non-Veg',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

              // Product name
              Expanded(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8),
                  child: Center(
                    child: Text(
                      product.name,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),

              // Price section
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFC107).withOpacity(0.2),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                ),
                child: Text(
                  NumberFormatter.formatCurrency(product.price),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFFFC107),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getCategoryEmoji(String categoryName) {
    final name = categoryName.toLowerCase();
    if (name.contains('momo') || name.contains('dumpling')) return '🥟';
    if (name.contains('wings') || name.contains('chicken')) return '🔥';
    if (name.contains('snack') || name.contains('late')) return '🌙';
    if (name.contains('veg') || name.contains('vegetable')) return '🥗';
    if (name.contains('drink') || name.contains('beverage')) return '🥤';
    if (name.contains('soup')) return '🍲';
    if (name.contains('rice') || name.contains('biryani')) return '🍚';
    if (name.contains('noodle')) return '🍜';
    if (name.contains('dessert') || name.contains('sweet')) return '🍰';
    return '🍽️'; // Default food emoji
  }
}
