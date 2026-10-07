import 'package:flutter/material.dart';
import '../widgets/auth_widgets.dart';
import '../widgets/logo_header.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('About Diagnostic System'),
        actions: const [AccountButton()],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const LogoHeader(height: 50),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🦠 Personalized Laboratory Test Recommendation System',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1565C0),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Offline Edge AI Diagnostic Tool for Viral Infections',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF00897B),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'System Overview',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'This standalone mobile application provides frontline healthcare workers and clinicians in Primary Health Centres (PHCs) and surveillance sites with fast, 100% offline edge neural network predictions to assist in identifying likely viral pathogens from patient symptoms and demographics.',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Technical Architecture',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  _buildBullet(
                      'Primary Model', 'Gated Residual Tabular Transformer (GRTT) for 24 major viral categories.'),
                  _buildBullet('Secondary Model',
                      'Sub-classification GRTT for 8 "Other Viruses" sub-categories.'),
                  _buildBullet('Inference Engine',
                      'ONNX Runtime Mobile with NPU/CPU hardware acceleration (<10 ms latency).'),
                  _buildBullet('Clinical Rules Engine',
                      'ICMR syndromic exclusion table and dynamic top-5 candidate promotion.'),
                  _buildBullet('Persistence & Security',
                      'Local offline encrypted SQLite database, atomic ID generation, de-identified record auditing.'),
                  const SizedBox(height: 20),
                  const Text(
                    'Collaborating Institutions',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _buildOrgTile(
                    'ICMR - National Institute of Epidemiology (NIE)',
                    'Chennai, Tamil Nadu',
                    Icons.account_balance,
                  ),
                  const SizedBox(height: 8),
                  _buildOrgTile(
                    'Department of Health Research (DHR)',
                    'Ministry of Health & Family Welfare, Govt. of India',
                    Icons.health_and_safety,
                  ),
                  const SizedBox(height: 8),
                  _buildOrgTile(
                    'Amity Centre for Artificial Intelligence (ACAI)',
                    'Amity University, Noida',
                    Icons.school,
                  ),
                  const SizedBox(height: 24),
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
                        Text(
                          '⚠️ Medical Disclaimer',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Color(0xFFC62828),
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'This application is an artificial intelligence-based decision support system designed solely for diagnostic assistance by healthcare professionals. It must not be used as a substitute for professional clinical judgment, laboratory confirmation, or medical diagnosis.',
                          style: TextStyle(fontSize: 11, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBullet(String title, String desc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.3),
                children: [
                  TextSpan(
                    text: '$title: ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: desc),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrgTile(String name, String sub, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF1565C0), size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  sub,
                  style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
