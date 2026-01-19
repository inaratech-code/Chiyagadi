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
  return replaced.replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');
}

/// Default image asset path derived from product name.
///
/// Example: "Masala Chiya" -> "assets/images/menu/masala_chiya.png"
String chiyagaadiImageAssetForName(String name) {
  final slug = _slugifyForAsset(name);
  return 'assets/images/menu/$slug.png';
}

const List<ChiyagaadiSeedCategory> chiyagaadiSeedCategories = [
  ChiyagaadiSeedCategory(name: 'Chiya (Tea)', displayOrder: 1),
  ChiyagaadiSeedCategory(name: 'Coffee', displayOrder: 2),
  ChiyagaadiSeedCategory(name: 'Drinks', displayOrder: 3),
  ChiyagaadiSeedCategory(name: 'Snacks', displayOrder: 4),
  ChiyagaadiSeedCategory(name: 'Hookah', displayOrder: 5),
  ChiyagaadiSeedCategory(name: 'Smokes', displayOrder: 6),
];

/// Menu items transcribed from the provided board photo.
///
/// If you want the Nepali names instead, just rename `name` fields.
const List<ChiyagaadiSeedProduct> chiyagaadiSeedProducts = [
  // Chiya (Tea)
  ChiyagaadiSeedProduct(
    categoryName: 'Chiya (Tea)',
    name: 'Masala Chiya',
    description: 'Spiced tea',
    price: 40,
    isVeg: true,
  ),
  ChiyagaadiSeedProduct(
    categoryName: 'Chiya (Tea)',
    name: 'Matka Chiya',
    description: 'Clay-pot tea',
    price: 70,
    isVeg: true,
  ),
  ChiyagaadiSeedProduct(
    categoryName: 'Chiya (Tea)',
    name: 'Black Chiya',
    description: 'Black tea',
    price: 30,
    isVeg: true,
  ),
  ChiyagaadiSeedProduct(
    categoryName: 'Chiya (Tea)',
    name: 'Lemon Chiya',
    description: 'Lemon tea',
    price: 35,
    isVeg: true,
  ),
  ChiyagaadiSeedProduct(
    categoryName: 'Chiya (Tea)',
    name: 'Edible Cup',
    description: 'Edible cup add-on',
    price: 110,
    isVeg: true,
  ),

  // Coffee
  ChiyagaadiSeedProduct(
    categoryName: 'Coffee',
    name: 'Black Coffee',
    description: 'Hot black coffee',
    price: 110,
    isVeg: true,
  ),
  ChiyagaadiSeedProduct(
    categoryName: 'Coffee',
    name: 'Milk Coffee',
    description: 'Hot milk coffee',
    price: 150,
    isVeg: true,
  ),
  ChiyagaadiSeedProduct(
    categoryName: 'Coffee',
    name: 'Cold Black Coffee',
    description: 'Iced black coffee',
    price: 140,
    isVeg: true,
  ),
  ChiyagaadiSeedProduct(
    categoryName: 'Coffee',
    name: 'Cold Milk Coffee',
    description: 'Iced milk coffee',
    price: 150,
    isVeg: true,
  ),

  // Drinks
  ChiyagaadiSeedProduct(
    categoryName: 'Drinks',
    name: 'Cold Drink',
    description: 'Soft drink',
    price: 40,
    isVeg: true,
  ),
  ChiyagaadiSeedProduct(
    categoryName: 'Drinks',
    name: 'Water',
    description: 'Bottled water',
    price: 15,
    isVeg: true,
  ),
  ChiyagaadiSeedProduct(
    categoryName: 'Drinks',
    name: 'Soda',
    description: 'Soda',
    price: 35,
    isVeg: true,
  ),
  ChiyagaadiSeedProduct(
    categoryName: 'Drinks',
    name: 'Juice',
    description: 'Juice',
    price: 50,
    isVeg: true,
  ),
  ChiyagaadiSeedProduct(
    categoryName: 'Drinks',
    name: 'Orange Juice',
    description: 'Orange juice',
    price: 60,
    isVeg: true,
  ),
  ChiyagaadiSeedProduct(
    categoryName: 'Drinks',
    name: 'Apple Juice',
    description: 'Apple juice',
    price: 60,
    isVeg: true,
  ),
  ChiyagaadiSeedProduct(
    categoryName: 'Drinks',
    name: 'Mixed Juice',
    description: 'Mixed juice',
    price: 70,
    isVeg: true,
  ),
  ChiyagaadiSeedProduct(
    categoryName: 'Drinks',
    name: 'Lassi',
    description: 'Lassi',
    price: 55,
    isVeg: true,
  ),
  ChiyagaadiSeedProduct(
    categoryName: 'Drinks',
    name: 'Mango Lassi',
    description: 'Mango lassi',
    price: 65,
    isVeg: true,
  ),

  // Snacks
  ChiyagaadiSeedProduct(
    categoryName: 'Snacks',
    name: 'Chicken Momo',
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
    name: 'Chowchow',
    description: 'Chowchow noodles',
    price: 100,
    isVeg: true,
  ),
  ChiyagaadiSeedProduct(
    categoryName: 'Snacks',
    name: 'Egg Omelette (1)',
    description: 'One egg omelette',
    price: 70,
    isVeg: false,
  ),

  // Hookah
  ChiyagaadiSeedProduct(
    categoryName: 'Hookah',
    name: 'Normal Hookah',
    description: 'Standard hookah',
    price: 350,
    isVeg: false,
  ),
  ChiyagaadiSeedProduct(
    categoryName: 'Hookah',
    name: 'Cloud Hookah',
    description: 'Premium cloud hookah',
    price: 450,
    isVeg: false,
  ),

  // Smokes
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

