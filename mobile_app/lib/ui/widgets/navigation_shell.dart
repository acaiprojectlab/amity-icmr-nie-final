import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../auth/auth_controller.dart';
import '../../auth/auth_models.dart';
import '../../providers/app_provider.dart';
import '../screens/home_screen.dart';
import '../screens/intake_wizard_screen.dart';
import '../screens/records_screen.dart';
import '../screens/about_screen.dart';
import 'auth_widgets.dart';

/// One navigation destination; which ones exist depends on the role.
class _NavTab {
  const _NavTab({
    required this.category,
    required this.icon,
    required this.label,
    required this.shortLabel,
    required this.screen,
  });

  final String category;
  final IconData icon;
  final String label; // desktop sidebar
  final String shortLabel; // bottom bar
  final Widget screen;
}

_NavTab _tabFor(AppPage page) => switch (page) {
      AppPage.home => const _NavTab(
          category: 'OVERVIEW',
          icon: Icons.home_rounded,
          label: 'Home',
          shortLabel: 'Home',
          screen: HomeScreen(showCaseMetrics: false),
        ),
      AppPage.dashboard => const _NavTab(
          category: 'OVERVIEW',
          icon: Icons.dashboard_rounded,
          label: 'Dashboard & KPIs',
          shortLabel: 'Dashboard',
          screen: HomeScreen(showCaseMetrics: true),
        ),
      AppPage.prediction => const _NavTab(
          category: 'CLINICAL WORKFLOW',
          icon: Icons.add_circle_outline_rounded,
          label: 'New Patient Intake',
          shortLabel: 'Intake',
          screen: IntakeWizardScreen(),
        ),
      AppPage.records => const _NavTab(
          category: 'DATA MANAGEMENT',
          icon: Icons.folder_shared_rounded,
          label: 'Patient Records',
          shortLabel: 'Records',
          screen: RecordsScreen(),
        ),
      AppPage.about => const _NavTab(
          category: 'SYSTEM & CONFIG',
          icon: Icons.info_outline_rounded,
          label: 'About & Guidelines',
          shortLabel: 'About',
          screen: AboutScreen(),
        ),
    };

class NavigationShell extends StatefulWidget {
  const NavigationShell({super.key});

  @override
  State<NavigationShell> createState() => _NavigationShellState();
}

class _NavigationShellState extends State<NavigationShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final auth = context.watch<AuthController>();
    // Only the sections this role may open are built at all (the auth gate
    // rebuilds this shell whenever the role changes).
    final tabs = auth.allowedPages.map(_tabFor).toList();
    final selected = _selectedIndex < tabs.length ? _selectedIndex : 0;
    final isDesktop = MediaQuery.of(context).size.width >= 700;
    const primaryBlue = Color(0xFF1565C0);
    const darkNavy = Color(0xFF0D1B2A);
    const sidebarBg = Color(0xFF1E293B);

    final Widget contentArea = provider.isInitializing
        ? const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading Edge ML Models & Datasets...'),
                ],
              ),
            ),
          )
        : provider.initError != null
            ? Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        Text('Initialization Error: ${provider.initError}'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => provider.initApp(),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : IndexedStack(
                index: selected,
                children: [for (final tab in tabs) tab.screen],
              );

    if (isDesktop) {
      return Scaffold(
        body: Row(
          children: [
            // LEFT SIDEBAR FOR DESKTOP
            Container(
              width: 260,
              color: sidebarBg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header / Branding
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                    decoration: BoxDecoration(
                      color: darkNavy,
                      border: Border(
                        bottom: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: primaryBlue,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.biotech, color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'ICMR-NIE & ACAI',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Diagnostic System',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Categorized Navigation Items
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      children: [
                        for (var i = 0; i < tabs.length; i++) ...[
                          if (i == 0 || tabs[i].category != tabs[i - 1].category) ...[
                            if (i > 0) const SizedBox(height: 16),
                            _buildCategoryHeader(tabs[i].category),
                          ],
                          _buildNavItem(
                            index: i,
                            selected: selected,
                            icon: tabs[i].icon,
                            label: tabs[i].label,
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Signed-in identity + role (tap for account options)
                  if (auth.session case final session?)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => showAccountSheet(context),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 10, 16, 0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  session.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              RoleBadge(role: session.role),
                            ],
                          ),
                        ),
                      ),
                    ),

                  // Footer status badge
                  Container(
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.greenAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Offline Edge AI Active',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // MAIN CONTENT
            Expanded(
              child: ClipRect(
                child: contentArea,
              ),
            ),
          ],
        ),
      );
    } else {
      // BOTTOM NAVIGATION BAR FOR MOBILE / TABLET
      return Scaffold(
        body: contentArea,
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: selected,
          onTap: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          selectedItemColor: primaryBlue,
          unselectedItemColor: Colors.grey.shade500,
          selectedFontSize: 12,
          unselectedFontSize: 11,
          elevation: 8,
          items: [
            for (final tab in tabs)
              BottomNavigationBarItem(
                icon: Icon(tab.icon),
                label: tab.shortLabel,
              ),
          ],
        ),
      );
    }
  }

  Widget _buildCategoryHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.4),
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required int selected,
    required IconData icon,
    required String label,
  }) {
    final isSelected = selected == index;
    const activeColor = Color(0xFF38BDF8); // Light Blue accent

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedIndex = index;
          });
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            color: isSelected ? activeColor.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isSelected
                ? Border.all(color: activeColor.withValues(alpha: 0.3), width: 1)
                : null,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected ? activeColor : Colors.white70,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.8),
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
              if (isSelected)
                Container(
                  width: 4,
                  height: 16,
                  decoration: BoxDecoration(
                    color: activeColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
