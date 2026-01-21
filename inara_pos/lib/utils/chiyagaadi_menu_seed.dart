/// Chiyagaadi default menu seed (categories + products).
///
/// Used to auto-populate a fresh database (SQLite or Firestore) so the POS
/// starts with the menu shown on your board.
///
/// Note: Images are derived from the item name using an asset path:
/// `assets/images/menu/<slug>.png`
///
/// You can drop images into that folder and they will show automatically.
library;

class ChiyagaadiSeedCategory {
  final String name;
  final int displayOrder;
  final bool isLocked;

  const ChiyagaadiSeedCategory({
    required this.name,
    required this.displayOrder,
    this.isLocked = false,
  });
}

class ChiyagaadiSeedProduct {
  final String categoryName;
  final String name;
  final String? description;
  final double price;
  final bool isVeg;
  final bool isActive;

  const ChiyagaadiSeedProduct({
    required this.categoryName,
    required this.name,
    required this.price,
    this.description,
    this.isVeg = true,
    this.isActive = true,
  });
}

String _slugifyForAsset(String name) {
  final trimmed = name.trim().toLowerCase();
  final replaced = trimmed.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  return replaced
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}

/// Default image asset path derived from product name.
///
/// Example: "Masala Chiya" -> "assets/images/menu/masala_chiya.png"
String chiyagaadiImageAssetForName(String name) {
  final slug = _slugifyForAsset(name);
  return 'assets/images/menu/$slug.png';
}

const List<ChiyagaadiSeedCategory> chiyagaadiSeedCategories = [
  ChiyagaadiSeedCategory(name: 'Tuto Sip', displayOrder: 1),
  ChiyagaadiSeedCategory(name: 'Chill Sip', displayOrder: 2),
  ChiyagaadiSeedCategory(name: 'Snacks', displayOrder: 3),
  ChiyagaadiSeedCategory(name: 'Hookah', displayOrder: 4),
  ChiyagaadiSeedCategory(name: 'Games & Vibes', displayOrder: 5),
  ChiyagaadiSeedCategory(name: 'Smokes', displayOrder: 6),
];

/// Menu items from the Chiyagaadi chalkboard menu.
///
/// Organized by sections: Tuto Sip, Chill Sip, Snacks, Hookah, Games & Vibes
const List<ChiyagaadiSeedProduct> chiyagaadiSeedProducts = [
  // Tuto Sip Section
  ChiyagaadiSeedProduct(
    categoryName: 'Tuto Sip',
    name: 'Masala Chiya',
    description: 'Spiced tea',
    price: 40,
    isVeg: true,
  ),
  ChiyagaadiSeedProduct(
    categoryName: 'Tuto Sip',
    name: 'Matka Chiya',
    description: 'Clay-pot tea',
    price: 70,
    isVeg: true,
  ),
  ChiyagaadiSeedProduct(
    categoryName: 'Tuto Sip',
    name: 'Edible Cup',
    description: 'Edible cup add-on',
    price: 30,
    isVeg: true,
  ),
  ChiyagaadiSeedProduct(
    categoryName: 'Tuto Sip',
    name: 'Black Chiya',
    description: 'Black tea',
    price: 30,
    isVeg: true,
  ),
  ChiyagaadiSeedProduct(
    categoryName: 'Tuto Sip',
    name: 'Lemon Chiya',
    description: 'Lemon tea',
    price: 35,
    isVeg: true,
  ),
  ChiyagaadiSeedProduct(
    categoryName: 'Tuto Sip',
    name: 'Black Coffee',
    description: 'Hot black coffee',
    price: 110,
    isVeg: true,
  ),
  ChiyagaadiSeedProduct(
    categoryName: 'Tuto Sip',
    name: 'Milk Coffee',
    description: 'Hot milk coffee',
    price: 150,
    isVeg: true,
  ),

  // Chill Sip Section
  ChiyagaadiSeedProduct(
    categoryName: 'Chill Sip',
    name: 'Pepsi / Slice / Dew',
    description: 'Soft drinks - Pepsi, Slice, or Mountain Dew',
    price: 80,
    isVeg: true,
  ),
  ChiyagaadiSeedProduct(
    categoryName: 'Chill Sip',
    name: 'Masala Cold Drink',
    description: 'Spiced cold drink',
    price: 110,
    isVeg: true,
  ),
  ChiyagaadiSeedProduct(
    categoryName: 'Chill Sip',
    name: 'Cold Black Coffee',
    description: 'Iced black coffee',
    price: 140,
    isVeg: true,
  ),
  ChiyagaadiSeedProduct(
    categoryName: 'Chill Sip',
    name: 'Cold Milk Coffee',
    description: 'Iced milk coffee',
    price: 160,
    isVeg: true,
  ),

  // Snacks Section
  ChiyagaadiSeedProduct(
    categoryName: 'Snacks',
    name: 'Chicken Mo-Mo',
    description: 'Chicken momos',
    price: 160,
    isVeg: false,
  ),
  ChiyagaadiSeedProduct(
    categoryName: 'Snacks',
    name: 'Sausage',
    description: 'Sausage snack',
    price: 80,
    isVeg: false,
  ),
  ChiyagaadiSeedProduct(
    categoryName: 'Snacks',
    name: 'Current Chowchow',
    description: 'Chowchow noodles',
    price: 100,
    isVeg: true,
  ),
  ChiyagaadiSeedProduct(
    categoryName: 'Snacks',
    name: '1 Egg Omelete',
    description: 'One egg omelette',
    price: 70,
    isVeg: false,
  ),

  // Hookah Section
  ChiyagaadiSeedProduct(
    categoryName: 'Hookah',
    name: 'Cloud Hookah',
    description: 'Premium cloud hookah',
    price: 450,
    isVeg: false,
  ),
  ChiyagaadiSeedProduct(
    categoryName: 'Hookah',
    name: 'Normal Hookah',
    description: 'Standard hookah',
    price: 350,
    isVeg: false,
  ),

  // Games & Vibes Section (free with order - set price to 0)
  ChiyagaadiSeedProduct(
    categoryName: 'Games & Vibes',
    name: 'Ludo / UNO / Chess / Stack',
    description: 'Games - Free with order',
    price: 0,
    isVeg: true,
  ),

  // Smokes (keeping existing items)
  ChiyagaadiSeedProduct(
    categoryName: 'Smokes',
    name: 'Marlboro',
    description: 'Cigarette',
    price: 150,
    isVeg: false,
  ),
  ChiyagaadiSeedProduct(
    categoryName: 'Smokes',
    name: 'Gold Flake',
    description: 'Cigarette',
    price: 120,
    isVeg: false,
  ),
  ChiyagaadiSeedProduct(
    categoryName: 'Smokes',
    name: '555',
    description: 'Cigarette',
    price: 130,
    isVeg: false,
  ),
  ChiyagaadiSeedProduct(
    categoryName: 'Smokes',
    name: 'Red & White',
    description: 'Cigarette',
    price: 110,
    isVeg: false,
  ),
];
