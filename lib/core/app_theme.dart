import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Official Wuarikes brand palette (--primary, --secondary, --accent, etc.)
class AppColors {
  static const primary = Color(0xFFC84B31);
  static const primaryLight = Color(0xFFE05D44);
  static const secondary = Color(0xFFECB365); // warm gold — also used for ratings
  static const accent = Color(0xFF606C38); // olive green
  static const primaryContainer = Color(0xFFF8DED4);
  static const onPrimaryContainer = Color(0xFFC84B31);
  static const surface = Color(0xFFFDFCF8); // --background
  static const surfaceContainerLowest = Color(0xFFFFFFFF); // --surface (cards)
  static const border = Color(0xFFE8E2D9);
  static const onSurface = Color(0xFF2D2424); // --text
  static const onSurfaceVariant = Color(0xFF7D7474); // --text-muted
  static const amber = secondary; // ratings
  static const outline = onSurfaceVariant;
}

/// Wuarikes corner-radius scale.
class AppRadius {
  static const lg = 24.0; // --radius-lg: 1.5rem
  static const xl = 40.0; // --radius-xl: 2.5rem
}

/// Soft, warm elevation — floating white cards on an off-white background,
/// no borders (Airbnb-style: shadow carries the hierarchy, not a hairline).
class AppShadows {
  static List<BoxShadow> card = [
    BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 16, offset: const Offset(0, 4)),
  ];
  static List<BoxShadow> raised = [
    BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 20, offset: const Offset(0, 6)),
  ];
}

class AppText {
  static TextStyle headlineLg = GoogleFonts.plusJakartaSans(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 40 / 32,
    letterSpacing: -0.5,
    color: AppColors.onSurface,
  );
  static TextStyle headlineMobile = GoogleFonts.plusJakartaSans(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 32 / 24,
    letterSpacing: -0.3,
    color: AppColors.onSurface,
  );
  static TextStyle titleLg = GoogleFonts.beVietnamPro(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    height: 28 / 20,
    color: AppColors.onSurface,
  );
  static TextStyle bodyLg = GoogleFonts.beVietnamPro(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 24 / 16,
    color: AppColors.onSurface,
  );
  static TextStyle bodyMd = GoogleFonts.beVietnamPro(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 20 / 14,
    color: AppColors.onSurfaceVariant,
  );
  static TextStyle labelMd = GoogleFonts.beVietnamPro(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 16 / 12,
    letterSpacing: 0.5,
    color: AppColors.onSurfaceVariant,
  );
}

ThemeData buildAppTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      surface: AppColors.surface,
    ),
    scaffoldBackgroundColor: AppColors.surface,
    fontFamily: GoogleFonts.beVietnamPro().fontFamily,
  );

  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      headlineLarge: AppText.headlineLg,
      headlineMedium: AppText.headlineMobile,
      titleLarge: AppText.titleLg,
      bodyLarge: AppText.bodyLg,
      bodyMedium: AppText.bodyMd,
      labelMedium: AppText.labelMd,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.primary,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: AppText.titleLg.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700),
      iconTheme: const IconThemeData(color: AppColors.onSurface),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surfaceContainerLowest,
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        textStyle: AppText.bodyLg.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.border),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.border.withValues(alpha: 0.35),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      hintStyle: AppText.bodyLg.copyWith(color: AppColors.onSurfaceVariant),
      labelStyle: AppText.bodyMd.copyWith(color: AppColors.onSurface, fontWeight: FontWeight.w500),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: AppColors.primary,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return AppText.labelMd.copyWith(
          color: selected ? AppColors.primary : Colors.grey.shade500,
          fontWeight: FontWeight.w600,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(color: selected ? Colors.white : Colors.grey.shade500);
      }),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: AppColors.surface,
      labelStyle: AppText.labelMd.copyWith(color: AppColors.onSurfaceVariant),
      side: const BorderSide(color: AppColors.border),
      shape: const StadiumBorder(),
    ),
  );
}
