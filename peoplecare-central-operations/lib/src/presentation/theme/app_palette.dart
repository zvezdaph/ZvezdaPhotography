import 'package:flutter/material.dart';

/// Colori applicativi oltre allo schema Material: barra laterale, stati,
/// priorità, calendario. Definiti per tema chiaro e scuro.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.canvas,
    required this.surface,
    required this.surfaceMuted,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.sidebar,
    required this.sidebarText,
    required this.sidebarMuted,
    required this.sidebarSelected,
    required this.sidebarAccent,
    required this.accent,
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.info,
    required this.infoSoft,
    required this.demoBanner,
    required this.demoBannerText,
    required this.gridLine,
    required this.gridLineStrong,
    required this.nowLine,
    required this.weekendTint,
    required this.hover,
  });

  final Color canvas;
  final Color surface;
  final Color surfaceMuted;
  final Color border;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color sidebar;
  final Color sidebarText;
  final Color sidebarMuted;
  final Color sidebarSelected;
  final Color sidebarAccent;
  final Color accent;
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color info;
  final Color infoSoft;
  final Color demoBanner;
  final Color demoBannerText;
  final Color gridLine;
  final Color gridLineStrong;
  final Color nowLine;
  final Color weekendTint;
  final Color hover;

  static const light = AppPalette(
    canvas: Color(0xFFF2F5F8),
    surface: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFF7F9FB),
    border: Color(0xFFE1E7EE),
    borderStrong: Color(0xFFC9D3DE),
    textPrimary: Color(0xFF17212B),
    textSecondary: Color(0xFF4F5D6C),
    textMuted: Color(0xFF7C8898),
    sidebar: Color(0xFF0E2B35),
    sidebarText: Color(0xFFE7F1F3),
    sidebarMuted: Color(0xFF8FB0B8),
    sidebarSelected: Color(0xFF17414D),
    sidebarAccent: Color(0xFF45C4C9),
    accent: Color(0xFF3A5BA9),
    success: Color(0xFF1E7B45),
    successSoft: Color(0xFFE1F4E8),
    warning: Color(0xFFB45309),
    warningSoft: Color(0xFFFDF0DC),
    danger: Color(0xFFC0342B),
    dangerSoft: Color(0xFFFCE4E2),
    info: Color(0xFF2563A6),
    infoSoft: Color(0xFFE1ECF8),
    demoBanner: Color(0xFFFFF3CD),
    demoBannerText: Color(0xFF7A5200),
    gridLine: Color(0xFFEDF1F5),
    gridLineStrong: Color(0xFFD7DFE7),
    nowLine: Color(0xFFD9352B),
    weekendTint: Color(0xFFF6F8FA),
    hover: Color(0xFFF0F5F8),
  );

  static const dark = AppPalette(
    canvas: Color(0xFF0E1419),
    surface: Color(0xFF151D24),
    surfaceMuted: Color(0xFF1A232B),
    border: Color(0xFF26323D),
    borderStrong: Color(0xFF36444F),
    textPrimary: Color(0xFFE6EDF3),
    textSecondary: Color(0xFFB0BCC8),
    textMuted: Color(0xFF7F8C99),
    sidebar: Color(0xFF0A1216),
    sidebarText: Color(0xFFDCE8EB),
    sidebarMuted: Color(0xFF7896A0),
    sidebarSelected: Color(0xFF15313A),
    sidebarAccent: Color(0xFF4FD1D6),
    accent: Color(0xFF8AA6F0),
    success: Color(0xFF5CC98A),
    successSoft: Color(0xFF16311F),
    warning: Color(0xFFF2A94A),
    warningSoft: Color(0xFF362612),
    danger: Color(0xFFF07167),
    dangerSoft: Color(0xFF3A1B19),
    info: Color(0xFF7BB0EE),
    infoSoft: Color(0xFF172A40),
    demoBanner: Color(0xFF3A2F12),
    demoBannerText: Color(0xFFF5D98B),
    gridLine: Color(0xFF1D2730),
    gridLineStrong: Color(0xFF2C3844),
    nowLine: Color(0xFFFF6B5E),
    weekendTint: Color(0xFF121A20),
    hover: Color(0xFF1C262F),
  );

  @override
  AppPalette copyWith() => this;

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      canvas: c(canvas, other.canvas),
      surface: c(surface, other.surface),
      surfaceMuted: c(surfaceMuted, other.surfaceMuted),
      border: c(border, other.border),
      borderStrong: c(borderStrong, other.borderStrong),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textMuted: c(textMuted, other.textMuted),
      sidebar: c(sidebar, other.sidebar),
      sidebarText: c(sidebarText, other.sidebarText),
      sidebarMuted: c(sidebarMuted, other.sidebarMuted),
      sidebarSelected: c(sidebarSelected, other.sidebarSelected),
      sidebarAccent: c(sidebarAccent, other.sidebarAccent),
      accent: c(accent, other.accent),
      success: c(success, other.success),
      successSoft: c(successSoft, other.successSoft),
      warning: c(warning, other.warning),
      warningSoft: c(warningSoft, other.warningSoft),
      danger: c(danger, other.danger),
      dangerSoft: c(dangerSoft, other.dangerSoft),
      info: c(info, other.info),
      infoSoft: c(infoSoft, other.infoSoft),
      demoBanner: c(demoBanner, other.demoBanner),
      demoBannerText: c(demoBannerText, other.demoBannerText),
      gridLine: c(gridLine, other.gridLine),
      gridLineStrong: c(gridLineStrong, other.gridLineStrong),
      nowLine: c(nowLine, other.nowLine),
      weekendTint: c(weekendTint, other.weekendTint),
      hover: c(hover, other.hover),
    );
  }
}

extension AppPaletteContext on BuildContext {
  AppPalette get palette => Theme.of(this).extension<AppPalette>()!;
}
