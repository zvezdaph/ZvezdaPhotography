import 'package:flutter/material.dart';

import '../../domain/domain.dart';

/// Colori e icona di uno stato, per tema chiaro o scuro.
@immutable
class StatusStyle {
  const StatusStyle({
    required this.foreground,
    required this.background,
    required this.border,
    required this.icon,
  });

  final Color foreground;
  final Color background;
  final Color border;
  final IconData icon;
}

bool _isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

StatusStyle _style(
  BuildContext context, {
  required int light,
  required int lightBg,
  required int dark,
  required IconData icon,
}) {
  final isDark = _isDark(context);
  final fg = Color(isDark ? dark : light);
  final bg = isDark ? fg.withValues(alpha: 0.16) : Color(lightBg);
  return StatusStyle(
    foreground: fg,
    background: bg,
    border: fg.withValues(alpha: isDark ? 0.45 : 0.35),
    icon: icon,
  );
}

StatusStyle serviceStatusStyle(BuildContext context, ServiceStatus status) =>
    switch (status) {
      ServiceStatus.daAssegnare => _style(
        context,
        light: 0xFF9A5B00,
        lightBg: 0xFFFEF1D6,
        dark: 0xFFF3B64E,
        icon: Icons.person_search_outlined,
      ),
      ServiceStatus.assegnato => _style(
        context,
        light: 0xFF2155A6,
        lightBg: 0xFFE3EDFB,
        dark: 0xFF86B1F2,
        icon: Icons.event_available_outlined,
      ),
      ServiceStatus.inCorso => _style(
        context,
        light: 0xFF00707A,
        lightBg: 0xFFC9F0F0,
        dark: 0xFF3FD8E0,
        icon: Icons.play_circle_outline,
      ),
      ServiceStatus.completato => _style(
        context,
        light: 0xFF3F7654,
        lightBg: 0xFFEDF4EF,
        dark: 0xFF8CC7A1,
        icon: Icons.check_circle_outline,
      ),
      ServiceStatus.annullato => _style(
        context,
        light: 0xFF66727F,
        lightBg: 0xFFECEFF3,
        dark: 0xFF98A5B3,
        icon: Icons.cancel_outlined,
      ),
      ServiceStatus.nonEseguito => _style(
        context,
        light: 0xFFB42A22,
        lightBg: 0xFFFCE3E1,
        dark: 0xFFF2847B,
        icon: Icons.report_gmailerrorred_outlined,
      ),
      ServiceStatus.daRiprogrammare => _style(
        context,
        light: 0xFF7A3DB8,
        lightBg: 0xFFF1E6FB,
        dark: 0xFFC39BF0,
        icon: Icons.update,
      ),
    };

StatusStyle priorityStyle(BuildContext context, ServicePriority priority) =>
    switch (priority) {
      ServicePriority.bassa => _style(
        context,
        light: 0xFF66727F,
        lightBg: 0xFFEEF1F4,
        dark: 0xFF98A5B3,
        icon: Icons.keyboard_arrow_down,
      ),
      ServicePriority.normale => _style(
        context,
        light: 0xFF3D5A80,
        lightBg: 0xFFE7EEF6,
        dark: 0xFF9DB6D8,
        icon: Icons.drag_handle,
      ),
      ServicePriority.alta => _style(
        context,
        light: 0xFFB45309,
        lightBg: 0xFFFDF0DC,
        dark: 0xFFF2A94A,
        icon: Icons.keyboard_double_arrow_up,
      ),
      ServicePriority.urgente => _style(
        context,
        light: 0xFFC0342B,
        lightBg: 0xFFFCE4E2,
        dark: 0xFFF07167,
        icon: Icons.priority_high,
      ),
    };

StatusStyle operatorStatusStyle(BuildContext context, OperatorStatus status) =>
    switch (status) {
      OperatorStatus.attivo => _style(
        context,
        light: 0xFF1E7B45,
        lightBg: 0xFFE1F4E8,
        dark: 0xFF6DD49A,
        icon: Icons.verified_user_outlined,
      ),
      OperatorStatus.sospeso => _style(
        context,
        light: 0xFFB45309,
        lightBg: 0xFFFDF0DC,
        dark: 0xFFF2A94A,
        icon: Icons.pause_circle_outline,
      ),
      OperatorStatus.disabilitato => _style(
        context,
        light: 0xFF66727F,
        lightBg: 0xFFECEFF3,
        dark: 0xFF98A5B3,
        icon: Icons.block,
      ),
    };

StatusStyle accountStatusStyle(BuildContext context, AccountStatus? status) =>
    switch (status) {
      AccountStatus.attivo => _style(
        context,
        light: 0xFF1E7B45,
        lightBg: 0xFFE1F4E8,
        dark: 0xFF6DD49A,
        icon: Icons.phone_android,
      ),
      AccountStatus.invitato => _style(
        context,
        light: 0xFF2155A6,
        lightBg: 0xFFE3EDFB,
        dark: 0xFF86B1F2,
        icon: Icons.mark_email_unread_outlined,
      ),
      AccountStatus.bloccato => _style(
        context,
        light: 0xFFC0342B,
        lightBg: 0xFFFCE4E2,
        dark: 0xFFF07167,
        icon: Icons.lock_outline,
      ),
      null => _style(
        context,
        light: 0xFF66727F,
        lightBg: 0xFFECEFF3,
        dark: 0xFF98A5B3,
        icon: Icons.no_accounts_outlined,
      ),
    };

StatusStyle changeRequestStatusStyle(
  BuildContext context,
  ChangeRequestStatus status,
) => switch (status) {
  ChangeRequestStatus.inAttesa => _style(
    context,
    light: 0xFFB45309,
    lightBg: 0xFFFDF0DC,
    dark: 0xFFF2A94A,
    icon: Icons.hourglass_top,
  ),
  ChangeRequestStatus.inLavorazione => _style(
    context,
    light: 0xFF2155A6,
    lightBg: 0xFFE3EDFB,
    dark: 0xFF86B1F2,
    icon: Icons.forum_outlined,
  ),
  ChangeRequestStatus.chiusa => _style(
    context,
    light: 0xFF1E7B45,
    lightBg: 0xFFE1F4E8,
    dark: 0xFF6DD49A,
    icon: Icons.task_alt,
  ),
};

StatusStyle severityStyle(
  BuildContext context,
  NotificationSeverity severity,
) => switch (severity) {
  NotificationSeverity.info => _style(
    context,
    light: 0xFF2563A6,
    lightBg: 0xFFE1ECF8,
    dark: 0xFF7BB0EE,
    icon: Icons.info_outline,
  ),
  NotificationSeverity.attenzione => _style(
    context,
    light: 0xFFB45309,
    lightBg: 0xFFFDF0DC,
    dark: 0xFFF2A94A,
    icon: Icons.warning_amber_rounded,
  ),
  NotificationSeverity.critica => _style(
    context,
    light: 0xFFC0342B,
    lightBg: 0xFFFCE4E2,
    dark: 0xFFF07167,
    icon: Icons.error_outline,
  ),
};

StatusStyle alertLevelStyle(BuildContext context, AlertLevel level) =>
    severityStyle(
      context,
      level == AlertLevel.critico
          ? NotificationSeverity.critica
          : NotificationSeverity.attenzione,
    );

/// Icona della notifica per tipo.
IconData notificationIcon(NotificationType type) => switch (type) {
  NotificationType.richiestaModifica => Icons.edit_calendar_outlined,
  NotificationType.servizioIniziato => Icons.play_circle_outline,
  NotificationType.servizioTerminato => Icons.check_circle_outline,
  NotificationType.documentoRicevuto => Icons.description_outlined,
  NotificationType.servizioProblematico => Icons.report_problem_outlined,
  NotificationType.operativa => Icons.campaign_outlined,
};

/// Icona per tipo di file.
IconData fileIcon(String extension) => switch (extension) {
  'pdf' => Icons.picture_as_pdf_outlined,
  'jpg' || 'jpeg' || 'png' => Icons.image_outlined,
  'doc' || 'docx' => Icons.article_outlined,
  'xls' || 'xlsx' || 'csv' => Icons.table_chart_outlined,
  _ => Icons.insert_drive_file_outlined,
};

/// Colore stabile associato a un testo (avatar, strutture, categorie).
Color colorForKey(BuildContext context, String key) {
  const palette = [
    Color(0xFF0E7C86),
    Color(0xFF3A5BA9),
    Color(0xFF8A4FBF),
    Color(0xFFB0602B),
    Color(0xFF2E7D4F),
    Color(0xFFB23A63),
    Color(0xFF4F6D7A),
    Color(0xFF7A6A1F),
  ];
  final hash = key.codeUnits.fold<int>(
    0,
    (acc, unit) => (acc * 31 + unit) & 0x7fffffff,
  );
  final color = palette[hash % palette.length];
  return _isDark(context) ? Color.lerp(color, Colors.white, 0.28)! : color;
}
