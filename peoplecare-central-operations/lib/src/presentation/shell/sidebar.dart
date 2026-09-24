import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../app_state/navigation_controller.dart';
import '../shared/widgets/badges.dart';
import '../theme/app_palette.dart';

/// Barra laterale di navigazione, raggruppata per area e con i contatori
/// delle attività in attesa.
class Sidebar extends StatelessWidget {
  const Sidebar({
    super.key,
    required this.collapsed,
    required this.onToggleCollapsed,
  });

  final bool collapsed;
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;
    final palette = context.palette;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: collapsed ? 72 : 272,
      color: palette.sidebar,
      child: ListenableBuilder(
        listenable: Listenable.merge([
          deps.navigation,
          deps.counters,
          deps.notifications,
        ]),
        builder: (context, _) {
          final groups = <String, List<AppSection>>{};
          for (final section in AppSection.values) {
            groups.putIfAbsent(section.group, () => []).add(section);
          }
          return Column(
            children: [
              _Brand(collapsed: collapsed),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Su schermi bassi (es. 1366x768, 1080p al 125-150%) le
                    // voci si compattano per restare tutte visibili.
                    final dense =
                        constraints.maxHeight <
                        16 + groups.length * 34 + AppSection.values.length * 45;
                    return ListView(
                      padding: EdgeInsets.symmetric(vertical: dense ? 4 : 8),
                      children: [
                        for (final MapEntry(key: group, value: sections)
                            in groups.entries) ...[
                          if (!collapsed)
                            Padding(
                              padding: dense
                                  ? const EdgeInsets.fromLTRB(22, 8, 16, 4)
                                  : const EdgeInsets.fromLTRB(22, 14, 16, 6),
                              child: Text(
                                group.toUpperCase(),
                                style: TextStyle(
                                  color: palette.sidebarMuted,
                                  fontSize: 11,
                                  letterSpacing: 0.8,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            )
                          else
                            SizedBox(height: dense ? 8 : 12),
                          for (final section in sections)
                            _SidebarItem(
                              section: section,
                              collapsed: collapsed,
                              dense: dense,
                              selected: deps.navigation.current == section,
                              badge: _badgeFor(deps, section),
                              onTap: () => deps.navigation.go(section),
                            ),
                        ],
                      ],
                    );
                  },
                ),
              ),
              _UserFooter(
                collapsed: collapsed,
                onToggleCollapsed: onToggleCollapsed,
              ),
            ],
          );
        },
      ),
    );
  }

  static int _badgeFor(AppDependencies deps, AppSection section) =>
      switch (section) {
        AppSection.changeRequests => deps.counters.pendingChangeRequests,
        AppSection.notifications => deps.notifications.unreadCount,
        AppSection.services => deps.counters.servicesToPlan,
        AppSection.documents => deps.counters.documentsToReview,
        _ => 0,
      };
}

class _Brand extends StatelessWidget {
  const _Brand({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      height: 68,
      padding: EdgeInsets.symmetric(horizontal: collapsed ? 16 : 18),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
        ),
      ),
      child: Row(
        children: [
          const BrandMark(size: 38),
          if (!collapsed) ...[
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PeopleCare',
                    style: TextStyle(
                      color: palette.sidebarText,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                  Text(
                    'Central Operations',
                    style: TextStyle(
                      color: palette.sidebarAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Marchio grafico dell'applicazione (disegnato, nessuna immagine esterna).
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3CC7C9), Color(0xFF0B6E79)],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.favorite, color: Colors.white, size: size * 0.58),
          Positioned(
            right: size * 0.14,
            bottom: size * 0.12,
            child: Container(
              width: size * 0.3,
              height: size * 0.3,
              decoration: const BoxDecoration(
                color: Color(0xFF0B6E79),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.add, color: Colors.white, size: size * 0.24),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.section,
    required this.collapsed,
    required this.dense,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  final AppSection section;
  final bool collapsed;
  final bool dense;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final selected = widget.selected;
    final foreground = selected ? Colors.white : palette.sidebarText;
    final background = selected
        ? palette.sidebarSelected
        : (_hover ? Colors.white.withValues(alpha: 0.05) : Colors.transparent);
    final item = MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: widget.dense ? 36 : 42,
          margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 1.5),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 22,
                decoration: BoxDecoration(
                  color: selected ? palette.sidebarAccent : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(width: widget.collapsed ? 13 : 11),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    selected
                        ? widget.section.selectedIcon
                        : widget.section.icon,
                    size: 21,
                    color: selected ? palette.sidebarAccent : foreground,
                  ),
                  if (widget.collapsed && widget.badge > 0)
                    Positioned(
                      right: -8,
                      top: -6,
                      child: Transform.scale(
                        scale: 0.8,
                        child: CountBadge(widget.badge),
                      ),
                    ),
                ],
              ),
              if (!widget.collapsed) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.section.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (widget.badge > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: CountBadge(
                      widget.badge,
                      color:
                          widget.section == AppSection.notifications ||
                              widget.section == AppSection.changeRequests
                          ? palette.danger
                          : palette.sidebarAccent.withValues(alpha: 0.9),
                      textColor:
                          widget.section == AppSection.notifications ||
                              widget.section == AppSection.changeRequests
                          ? Colors.white
                          : palette.sidebar,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
    if (!widget.collapsed) return item;
    return Tooltip(
      message: widget.badge > 0
          ? '${widget.section.title} (${widget.badge})'
          : widget.section.title,
      preferBelow: false,
      verticalOffset: 0,
      margin: const EdgeInsets.only(left: 70),
      child: item,
    );
  }
}

class _UserFooter extends StatelessWidget {
  const _UserFooter({required this.collapsed, required this.onToggleCollapsed});

  final bool collapsed;
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final deps = context.deps;
    final palette = context.palette;
    final user = deps.currentUser;
    final source = deps.dataSource;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.07)),
        ),
      ),
      padding: EdgeInsets.fromLTRB(collapsed ? 12 : 16, 12, 8, 12),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: palette.sidebarAccent.withValues(alpha: 0.2),
                child: Text(
                  user.initials,
                  style: TextStyle(
                    color: palette.sidebarAccent,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              if (!collapsed) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.sidebarText,
                          fontWeight: FontWeight.w600,
                          fontSize: 13.5,
                        ),
                      ),
                      Text(
                        user.role,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.sidebarMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (!collapsed)
                Expanded(
                  child: Tooltip(
                    message: source.description ?? source.name,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: source.isDemo
                            ? const Color(0xFFF2B640).withValues(alpha: 0.16)
                            : palette.sidebarAccent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            source.isDemo
                                ? Icons.science_outlined
                                : Icons.cloud_done_outlined,
                            size: 15,
                            color: source.isDemo
                                ? const Color(0xFFF2B640)
                                : palette.sidebarAccent,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              source.isDemo
                                  ? 'Dati DEMO'
                                  : 'Sistema ${source.name}',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: source.isDemo
                                    ? const Color(0xFFF2B640)
                                    : palette.sidebarAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              IconButton(
                tooltip: collapsed ? 'Espandi menu' : 'Comprimi menu',
                onPressed: onToggleCollapsed,
                icon: Icon(
                  collapsed
                      ? Icons.keyboard_double_arrow_right
                      : Icons.keyboard_double_arrow_left,
                  color: palette.sidebarMuted,
                  size: 20,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
