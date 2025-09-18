// lib/widgets/drawer_menu.dart
import 'package:flutter/material.dart';
import 'package:led_digital_scroll/screens/privacy_policy.dart';
import 'package:led_digital_scroll/widgets/rate_dialog.dart';

class DrawerMenu extends StatelessWidget {
  final ValueChanged<String>? onShareApp;
  const DrawerMenu({super.key, this.onShareApp});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF121214),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            const SizedBox(height: 8),
            const ListTile(
              title: Text(
                'Digital LED Signboard',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.star_rate_rounded, color: Colors.white),
              title: const Text(
                'Rate App',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => showDialog(
                context: context,
                builder: (_) => const RateDialog(),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.share, color: Colors.white),
              title: const Text(
                'Share App',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () {
                if (onShareApp != null)
                  onShareApp!(
                    "https://play.google.com/store/apps/details?id=com.example.myapp",
                  );
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.privacy_tip_outlined,
                color: Colors.white,
              ),
              title: const Text(
                'Privacy Policy',
                style: TextStyle(color: Colors.white),
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PrivacyPolicy()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
