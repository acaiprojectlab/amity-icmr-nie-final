import 'package:flutter/material.dart';

class LogoHeader extends StatelessWidget {
  final double height;
  final bool compact;

  const LogoHeader({
    super.key,
    this.height = 48.0,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ICMR Logo
          Image.asset(
            'assets/images/logo_1.jpeg',
            height: height,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const Text(
              'ICMR-NIE',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          Container(
            height: height * 0.7,
            width: 1,
            color: Colors.grey.withValues(alpha: 0.3),
          ),
          // DHR Logo
          Image.asset(
            'assets/images/logo_2.jpeg',
            height: height * 0.9,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const Text(
              'DHR',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          Container(
            height: height * 0.7,
            width: 1,
            color: Colors.grey.withValues(alpha: 0.3),
          ),
          // Amity Logo
          Image.asset(
            'assets/images/Amity_logo2.png',
            height: height * 0.9,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => const Text(
              'AMITY',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
