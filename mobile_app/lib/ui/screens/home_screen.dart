import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/app_provider.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/kpi_card.dart';
import '../widgets/logo_header.dart';
import 'about_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, this.showCaseMetrics = false});

  /// Case-status and enrollment KPIs: the admin "Dashboard". Standard users
  /// get the Home page without them, as on the web.
  final bool showCaseMetrics;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final metrics = provider.metrics;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'ICMR-NIE & ACAI Diagnostic System',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'About System',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutScreen()),
              );
            },
          ),
          const AccountButton(),
        ],
      ),
      body: provider.isInitializing
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading Edge ML Models & Datasets...'),
                ],
              ),
            )
          : provider.initError != null
              ? Center(
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
                )
              : RefreshIndicator(
                  onRefresh: () => provider.refreshDashboard(),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Institutional Logos Strip
                        const LogoHeader(height: 44),

                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Hero Title Card
                              Container(
                                padding: const EdgeInsets.all(18.0),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF1565C0),
                                      Color(0xFF0D47A1)
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(14.0),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF1565C0)
                                          .withValues(alpha: 0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Text(
                                          '🦠 ',
                                          style: TextStyle(fontSize: 22),
                                        ),
                                        Expanded(
                                          child: Text(
                                            'Personalized Laboratory Test Recommendation System',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              height: 1.2,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Offline Edge AI Diagnostic Tool with Dual-Stage Tabular Transformers for Viral Infections',
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.9),
                                        fontSize: 12,
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 20),

                              if (!showCaseMetrics) ...[
                                const Text(
                                  'This tool analyses a patient’s symptoms, '
                                  'demographics and location to recommend the '
                                  'most probable viral infections to test for.',
                                  style: TextStyle(fontSize: 13.5, height: 1.45),
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'Open the Intake tab to enter patient details '
                                  'and get a test recommendation.',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    height: 1.45,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1565C0),
                                  ),
                                ),
                                const SizedBox(height: 20),
                              ],

                              if (showCaseMetrics) ...[
                                // Section: Patient & DR Status KPIs
                                const Text(
                                  '📊 Case Status Metrics',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                GridView.count(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 8,
                                  mainAxisSpacing: 8,
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  childAspectRatio: 1.05,
                                  children: [
                                    KpiCard(
                                      value: metrics.enrolled,
                                      label: 'Enrolled Records',
                                      backgroundColor: const Color(0xFF3C8DBC),
                                      icon: Icons.people_outline,
                                    ),
                                    KpiCard(
                                      value: metrics.drCompleted,
                                      label: 'DR Completed',
                                      backgroundColor: const Color(0xFF00A65A),
                                      icon: Icons.check_circle_outline,
                                    ),
                                    KpiCard(
                                      value: metrics.drPending,
                                      label: 'DR Pending',
                                      backgroundColor: const Color(0xFFDD4B39),
                                      icon: Icons.pending_outlined,
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 16),

                                // Section: Enrollment Trends KPIs
                                const Text(
                                  '📈 Enrollment Timeline',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                GridView.count(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 8,
                                  mainAxisSpacing: 8,
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  childAspectRatio: 1.05,
                                  children: [
                                    KpiCard(
                                      value: metrics.daily,
                                      label: 'Enrolled Today',
                                      backgroundColor: const Color(0xFF00C0EF),
                                      icon: Icons.today,
                                    ),
                                    KpiCard(
                                      value: metrics.weekly,
                                      label: 'Last 7 Days',
                                      backgroundColor: const Color(0xFFF39C12),
                                      icon: Icons.date_range,
                                    ),
                                    KpiCard(
                                      value: metrics.monthly,
                                      label: 'Last 30 Days',
                                      backgroundColor: const Color(0xFF605CA8),
                                      icon: Icons.calendar_month,
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 20),
                              ],

                              // Medical Disclaimer Card
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF5F5),
                                  borderRadius: BorderRadius.circular(8),
                                  border: const Border(
                                    left: BorderSide(
                                      color: Color(0xFFEF5350),
                                      width: 4,
                                    ),
                                  ),
                                ),
                                child: const Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.warning_amber_rounded,
                                            color: Color(0xFFEF5350), size: 18),
                                        SizedBox(width: 6),
                                        Text(
                                          'Medical Disclaimer',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: Color(0xFFC62828),
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'This system assists healthcare professionals and should not replace professional medical diagnosis. Always consult qualified medical personnel for patient care decisions.',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF424242),
                                        height: 1.3,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }
}
