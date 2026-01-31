import 'package:flutter/foundation.dart' show kIsWeb;
import '../providers/unified_database_provider.dart';

/// Inventory Category Helper
///
/// Determines which categories allow inventory tracking (countable items only).
/// Only Food, Cold Drinks, Cigarettes, Smokes, and Snacks can have inventory added/updated.

/// Categories that allow inventory tracking (countable items)
const Set<String> _inventoryAllowedCategories = {
  'Food',
  'Cold Drinks',
  'Cigarettes',
  'Smokes',
  'Snacks',
};

/// Categories that do NOT allow inventory tracking
const Set<String> _inventoryExcludedCategories = {
  'Tea',
  'Coffee',
  'Drinks',
  'Hookah',
};

/// Checks if a category allows inventory tracking
///
/// Returns true only for countable items:
/// - Food
/// - Cold Drinks
/// - Cigarettes
/// - Smokes
/// - Snacks
///
/// Returns false for excluded categories:
/// - Tea / Coffee / Drinks
/// - Hookah
///
/// Case-insensitive matching.
bool canTrackInventoryForCategory(String categoryName) {
  final normalized = categoryName.trim();

  // Check excluded categories first (more specific)
  for (final excluded in _inventoryExcludedCategories) {
    if (normalized.toLowerCase() == excluded.toLowerCase()) {
      return false;
    }
  }

  // Check allowed categories
  for (final allowed in _inventoryAllowedCategories) {
    if (normalized.toLowerCase() == allowed.toLowerCase()) {
      return true;
    }
  }

  // Default: no tracking
  return false;
}

/// Validates if a product can have inventory added/updated based on its category
///
/// Throws an exception if the category doesn't allow inventory tracking.
Future<void> validateInventoryAllowed({
  required UnifiedDatabaseProvider dbProvider,
  required dynamic productId,
}) async {
  await dbProvider.init();

  // Get product data
  final productData = await dbProvider.query(
    'products',
    where: kIsWeb ? 'documentId = ?' : 'id = ?',
    whereArgs: [productId],
  );

  if (productData.isEmpty) {
    throw Exception('Product not found');
  }

  final categoryId = productData.first['category_id'];
  if (categoryId == null) {
    throw Exception('Product has no category assigned');
  }

  // Get category name
  final categoryData = await dbProvider.query(
    'categories',
    where: kIsWeb ? 'documentId = ?' : 'id = ?',
    whereArgs: [categoryId],
  );

  if (categoryData.isEmpty) {
    throw Exception('Category not found');
  }

  final categoryName = categoryData.first['name'] as String? ?? '';

  if (!canTrackInventoryForCategory(categoryName)) {
    throw Exception(
        'Inventory tracking is not allowed for "${categoryName}" category. '
        'Only Food, Cold Drinks, Cigarettes, Smokes, and Snacks can have inventory.');
  }
}
