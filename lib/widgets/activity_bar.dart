import 'package:flutter/material.dart';

enum SidebarTab { explorer, search, sourceControl }

class ActivityBar extends StatelessWidget {
  final SidebarTab? activeTab;
  final ValueChanged<SidebarTab> onTabSelected;
  final int sourceControlBadgeCount;

  const ActivityBar({
    super.key,
    required this.activeTab,
    required this.onTabSelected,
    this.sourceControlBadgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF181818);
    const border = Color(0xFF282828);

    return Container(
      width: 50,
      decoration: const BoxDecoration(
        color: bg,
        border: Border(
          right: BorderSide(color: border, width: 1),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 6),
          _buildActivityItem(
            tab: SidebarTab.explorer,
            icon: Icons.copy,
            tooltip: 'Explorer (Ctrl+Shift+E)',
          ),
          _buildActivityItem(
            tab: SidebarTab.search,
            icon: Icons.search,
            tooltip: 'Search (Ctrl+Shift+F)',
          ),
          _buildActivityItem(
            tab: SidebarTab.sourceControl,
            icon: Icons.fork_right,
            tooltip: 'Source Control (Ctrl+Shift+G)',
            badgeCount: sourceControlBadgeCount,
          ),
          const Spacer(),
          // Settings icon at the bottom
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 22),
            color: const Color(0xFF858585),
            tooltip: 'Settings',
            onPressed: () {},
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildActivityItem({
    required SidebarTab tab,
    required IconData icon,
    required String tooltip,
    int badgeCount = 0,
  }) {
    final isSelected = activeTab == tab;
    const activeColor = Colors.white;
    const inactiveColor = Color(0xFF858585);
    const indicatorColor = Color(0xFF0078D4);

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: InkWell(
        onTap: () => onTabSelected(tab),
        child: SizedBox(
          width: 50,
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Active left indicator bar
              if (isSelected)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 2.5,
                    color: indicatorColor,
                  ),
                ),
              // Icon
              Icon(
                icon,
                size: 24,
                color: isSelected ? activeColor : inactiveColor,
              ),
              // Badge count
              if (badgeCount > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0078D4),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    child: Text(
                      badgeCount > 99 ? '99+' : '$badgeCount',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

