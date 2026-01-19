import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Logo Color Scheme
  static const Color logoPrimary = Color(0xFFFFC107); // Warm golden yellow
  static const Color logoSecondary = Color(0xFFFFB300); // Darker golden
  static const Color logoAccent = Color(0xFF8B4513); // Brown
  static const Color logoLight = Color(0xFFFFEB3B); // Light yellow

  // Semantic colors using logo scheme
  static const Color successColor = Color(0xFF4CAF50); // Keep green for success
  static const Color errorColor = Color(0xFFE53935); // Keep red for errors
  static const Color warningColor =
      Color(0xFFFFB300); // Use logo secondary for warnings
  static const Color infoColor = Color(0xFFFFC107); // Use logo primary for info

  // Typography
  // - Body text uses the platform default font (Roboto/SF/etc.)
  // - Headings use a distinct font for stronger hierarchy

  static TextTheme _buildTextTheme({
    required Color headingColor,
    required Color bodyColor,
    required Color secondaryBodyColor,
  }) {
    // Use GoogleFonts for headings only; body keeps the platform default.
    TextStyle h(double size, FontWeight weight) => GoogleFonts.poppins(
          fontSize: size,
          fontWeight: weight,
          color: headingColor,
          height: 1.15,
        );

    return TextTheme(
      // Big headings
      displayLarge: h(52, FontWeight.w800),
      displayMedium: h(40, FontWeight.w800),
      displaySmall: h(30, FontWeight.w700),

      // Section headings
      headlineLarge: h(28, FontWeight.w700),
      headlineMedium: h(22, FontWeight.w700),
      headlineSmall: h(20, FontWeight.w600),

      // Card/dialog titles
      titleLarge: h(18, FontWeight.w600),
      titleMedium: h(16, FontWeight.w600),
      titleSmall: h(14, FontWeight.w600),

      // Body
      bodyLarge: TextStyle(fontSize: 16, color: bodyColor, height: 1.35),
      bodyMedium:
          TextStyle(fontSize: 14, color: secondaryBodyColor, height: 1.35),
      bodySmall:
          TextStyle(fontSize: 12, color: secondaryBodyColor, height: 1.35),

      // Labels
      labelLarge: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w600, color: bodyColor),
      labelMedium: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w600, color: secondaryBodyColor),
      labelSmall: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w500, color: secondaryBodyColor),
    ).apply(
      // Ensure we always prefer the heading font for headings even if other widgets
      // call `copyWith(fontFamily: ...)` elsewhere.
      fontFamily: null,
    );
  }

  static TextStyle _appBarTitleStyle({required Color color}) {
    return GoogleFonts.poppins(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      color: color,
      height: 1.1,
    );
  }

  // POS Theme (for billing screens) - Colorful Tea Café Theme
  static ThemeData get darkTheme {
    const appBg = Color(0xFFF6EBCB); // slightly darker warm background
    const cardBg = Color(0xFFFFFDE7);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light, // Changed to light for colorful backgrounds
      primaryColor: logoPrimary,
      primarySwatch: _createMaterialColor(logoPrimary),
      colorScheme: ColorScheme.fromSeed(
        seedColor: logoPrimary,
        brightness: Brightness.light,
        background: appBg,
        surface: cardBg,
      ),
      scaffoldBackgroundColor: appBg, // Slightly darker warm background
      cardColor: cardBg, // Light golden card background
      dividerColor: logoSecondary.withOpacity(0.3),
      appBarTheme: AppBarTheme(
        backgroundColor: logoLight.withOpacity(0.8), // Light golden app bar
        elevation: 2,
        iconTheme: const IconThemeData(color: logoAccent),
        titleTextStyle: _appBarTitleStyle(color: logoAccent),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: logoPrimary,
          foregroundColor: logoAccent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          minimumSize: const Size(88, 44), // Web-friendly touch target
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ).copyWith(
          // Web hover effect
          backgroundColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.hovered)) {
              return logoSecondary;
            }
            return logoPrimary;
          }),
        ),
      ),
      textTheme: _buildTextTheme(
        headingColor: logoAccent,
        bodyColor: logoAccent,
        secondaryBodyColor: const Color(0xFF5D4037),
      ),
      navigationBarTheme: NavigationBarThemeData(
        labelTextStyle: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            );
          }
          return const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
          );
        }),
      ),
    );
  }

  // Light Theme (for admin/settings screens) - Colorful Tea Café Theme
  static ThemeData get lightTheme {
    const appBg = Color(0xFFF4E7C4); // slightly darker warm background
    const cardBg = Color(0xFFFFFDE7);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      primaryColor: logoPrimary,
      primarySwatch: _createMaterialColor(logoPrimary),
      colorScheme: ColorScheme.fromSeed(
        seedColor: logoPrimary,
        brightness: Brightness.light,
        background: appBg,
        surface: cardBg,
      ),
      scaffoldBackgroundColor: appBg, // Slightly darker warm background
      cardColor: cardBg, // Light golden card background
      dividerColor: logoSecondary.withOpacity(0.3),
      appBarTheme: AppBarTheme(
        backgroundColor: logoLight.withOpacity(0.9), // Light golden app bar
        elevation: 2,
        iconTheme: const IconThemeData(color: logoAccent),
        titleTextStyle: _appBarTitleStyle(color: logoAccent),
        shadowColor: logoSecondary.withOpacity(0.2),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: logoPrimary,
          foregroundColor: logoAccent,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          minimumSize: const Size(88, 44), // Web-friendly touch target
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ).copyWith(
          // Web hover effect
          backgroundColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.hovered)) {
              return logoSecondary;
            }
            return logoPrimary;
          }),
        ),
      ),
      textTheme: _buildTextTheme(
        headingColor: const Color(0xFF1E1E1E),
        bodyColor: const Color(0xFF1E1E1E),
        secondaryBodyColor: Colors.grey,
      ),
      navigationBarTheme: NavigationBarThemeData(
        labelTextStyle: MaterialStateProperty.resolveWith((states) {
          if (states.contains(MaterialState.selected)) {
            return const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            );
          }
          return const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
          );
        }),
      ),
    );
  }

  // POS Screen Theme (dark with large totals)
  static ThemeData get posTheme => darkTheme;

  // Helper to create MaterialColor from a single color
  static MaterialColor _createMaterialColor(Color color) {
    List strengths = <double>[.05];
    Map<int, Color> swatch = {};
    final int r = color.red, g = color.green, b = color.blue;

    for (int i = 1; i < 10; i++) {
      strengths.add(0.1 * i);
    }
    for (var strength in strengths) {
      final double ds = 0.5 - strength;
      swatch[(strength * 1000).round()] = Color.fromRGBO(
        r + ((ds < 0 ? r : (255 - r)) * ds).round(),
        g + ((ds < 0 ? g : (255 - g)) * ds).round(),
        b + ((ds < 0 ? b : (255 - b)) * ds).round(),
        1,
      );
    }
    return MaterialColor(color.value, swatch);
  }
}
