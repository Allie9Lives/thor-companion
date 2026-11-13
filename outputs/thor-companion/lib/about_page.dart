import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'ui.dart';

const aboutBridge = MethodChannel('com.alan.thorCompanion/about');

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});
  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  late final version = loadVersion();
  Future<Map<String, dynamic>?> loadVersion() async {
    try {
      return await aboutBridge.invokeMapMethod<String, dynamic>('version');
    } catch (_) {
      return null;
    }
  }

  Future<void> github() async {
    try {
      await aboutBridge.invokeMethod<void>('github');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Couldn’t open GitHub.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 16),
          Center(
            child: Container(
              width: 80,
              height: 80,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: p.accent,
                borderRadius: BorderRadius.circular(22),
              ),
              child: CustomPaint(painter: HandheldPainter(color: p.onAccent)),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Thor Companion',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          FutureBuilder<Map<String, dynamic>?>(
            future: version,
            builder: (context, snapshot) => Text(
              snapshot.data == null
                  ? ''
                  : 'Version ${snapshot.data!['version']} (${snapshot.data!['build']})',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: p.secondaryText),
            ),
          ),
          const SizedBox(height: 28),
          surface(
            padding: EdgeInsets.zero,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 10,
              ),
              leading: ClipOval(
                child: Image.asset(
                  'assets/author-avatar.png',
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  semanticLabel: 'Allie Stark’s GitHub avatar',
                ),
              ),
              title: const Text('@Allie9Lives'),
              subtitle: const Text('GitHub'),
              trailing: const Icon(Icons.open_in_new, size: 20),
              onTap: github,
            ),
          ),
          const SizedBox(height: 28),
          Text(
            '© 2026 Allie Stark (Allie9Lives)',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: p.secondaryText),
          ),
        ],
      ),
    );
  }
}
