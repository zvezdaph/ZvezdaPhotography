import 'package:flutter/material.dart';

import 'app_palette.dart';

/// Temi dell'applicazione, pensati per monitor desktop 1080p e superiori:
/// testo 14 px, contrasti elevati, superfici chiare e bordi sottili.
abstract final class AppTheme {
  static const _primaryLight = Color(0xFF0B6E79);
  static const _primaryDark = Color(0xFF4FC3CC);

  static ThemeData light() => _build(
    brightness: Brightness.light,
    palette: AppPalette.light,
    primary: _primaryLight,
  );

  static ThemeData dark() => _build(
    brightness: Brightness.dark,
    palette: AppPalette.dark,
    primary: _primaryDark,
  );

  static ThemeData _build({
    required Brightness brightness,
    required AppPalette palette,
    required Color primary,
  }) {
    final isDark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: _primaryLight,
          brightness: brightness,
        ).copyWith(
          primary: primary,
          onPrimary: isDark ? const Color(0xFF00292E) : Colors.white,
          secondary: palette.accent,
          surface: palette.surface,
          onSurface: palette.textPrimary,
          onSurfaceVariant: palette.textSecondary,
          surfaceContainerLowest: palette.surface,
          surfaceContainerLow: palette.surfaceMuted,
          surfaceContainer: palette.surfaceMuted,
          surfaceContainerHigh: palette.surface,
          surfaceContainerHighest: palette.surfaceMuted,
          outline: palette.borderStrong,
          outlineVariant: palette.border,
          error: palette.danger,
        );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
    final text = base.textTheme.apply(
      bodyColor: palette.textPrimary,
      displayColor: palette.textPrimary,
    );
    final textTheme = text.copyWith(
      headlineSmall: text.headlineSmall?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleLarge: text.titleLarge?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: text.titleMedium?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      titleSmall: text.titleSmall?.copyWith(
        fontSize: 13.5,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: text.bodyLarge?.copyWith(fontSize: 15),
      bodyMedium: text.bodyMedium?.copyWith(fontSize: 14, height: 1.35),
      bodySmall: text.bodySmall?.copyWith(
        fontSize: 12.5,
        color: palette.textSecondary,
      ),
      labelLarge: text.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: text.labelMedium?.copyWith(fontSize: 12.5),
      labelSmall: text.labelSmall?.copyWith(fontSize: 11.5),
    );

    final radius = BorderRadius.circular(8);
    final inputBorder = OutlineInputBorder(
      borderRadius: radius,
      borderSide: BorderSide(color: palette.borderStrong),
    );

    return base.copyWith(
      scaffoldBackgroundColor: palette.canvas,
      canvasColor: palette.surface,
      dividerColor: palette.border,
      textTheme: textTheme,
      extensions: [palette],
      dividerTheme: DividerThemeData(
        color: palette.border,
        thickness: 1,
        space: 1,
      ),
      cardTheme: CardThemeData(
        color: palette.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: palette.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: palette.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: palette.danger),
        ),
        focusedErrorBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: palette.danger, width: 1.6),
        ),
        disabledBorder: inputBorder.copyWith(
          borderSide: BorderSide(color: palette.border),
        ),
        labelStyle: TextStyle(color: palette.textSecondary),
        floatingLabelStyle: TextStyle(color: scheme.primary),
        hintStyle: TextStyle(color: palette.textMuted),
        helperStyle: TextStyle(color: palette.textMuted, fontSize: 12),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          foregroundColor: palette.textPrimary,
          side: BorderSide(color: palette.borderStrong),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: textTheme.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: palette.textSecondary,
          shape: RoundedRectangleBorder(borderRadius: radius),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: radius),
          ),
          side: WidgetStatePropertyAll(BorderSide(color: palette.borderStrong)),
          textStyle: WidgetStatePropertyAll(textTheme.labelMedium),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.surface,
        selectedColor: scheme.primary.withValues(alpha: isDark ? 0.25 : 0.12),
        side: BorderSide(color: palette.borderStrong),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        labelStyle: textTheme.labelMedium?.copyWith(color: palette.textPrimary),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        showCheckmark: true,
        checkmarkColor: scheme.primary,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        titleTextStyle: textTheme.titleLarge,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: palette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: palette.border),
        ),
        textStyle: textTheme.bodyMedium,
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(palette.surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: palette.border),
            ),
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 450),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12.5),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2B3844) : const Color(0xFF1E2A35),
          borderRadius: BorderRadius.circular(6),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        width: 520,
        backgroundColor: isDark
            ? const Color(0xFF26323D)
            : const Color(0xFF1E2A35),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: palette.textSecondary,
        indicatorColor: scheme.primary,
        dividerColor: palette.border,
        labelStyle: textTheme.labelLarge,
        unselectedLabelStyle: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w500,
        ),
        tabAlignment: TabAlignment.start,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(8),
        radius: const Radius.circular(8),
        thumbColor: WidgetStatePropertyAll(
          palette.textMuted.withValues(alpha: 0.45),
        ),
      ),
      listTileTheme: ListTileThemeData(
        dense: true,
        iconColor: palette.textSecondary,
        shape: RoundedRectangleBorder(borderRadius: radius),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: palette.border,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
      ),
      timePickerTheme: TimePickerThemeData(backgroundColor: palette.surface),
    );
  }
}
