import 'package:flutter/material.dart';

/// iOS owns the system bond; the app can guide removal, then scan afresh.
Future<bool> showPairingRecovery(BuildContext context) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => const _PairingRecovery(),
    ) ??
    false;

class _PairingRecovery extends StatefulWidget {
  const _PairingRecovery();
  @override
  State<_PairingRecovery> createState() => _PairingRecoveryState();
}

class _PairingRecoveryState extends State<_PairingRecovery> {
  bool forgotten = false;

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Repair connection',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          const Text(
            'Your iPhone has outdated Bluetooth pairing information. Automatic retries are paused.',
          ),
          const SizedBox(height: 24),
          _step(
            1,
            'Forget the system pairing',
            'Open iPhone Settings → Bluetooth. Tap ⓘ beside your Thor, then Forget This Device.',
          ),
          const SizedBox(height: 20),
          _step(
            2,
            'Find your Thor again',
            'Return here and scan. Choose the Thor from Nearby devices.',
          ),
          const SizedBox(height: 20),
          _step(
            3,
            'Confirm pairing',
            'Keep the Thor open with monitoring running. Accept any pairing prompts on both devices.',
          ),
          const SizedBox(height: 20),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('I’ve forgotten the Thor in iPhone Settings'),
            value: forgotten,
            onChanged: (value) => setState(() => forgotten = value ?? false),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: forgotten ? () => Navigator.pop(context, true) : null,
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text('Scan for Thor'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _step(int number, String title, String detail) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CircleAvatar(radius: 16, child: Text('$number')),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(detail),
          ],
        ),
      ),
    ],
  );
}
