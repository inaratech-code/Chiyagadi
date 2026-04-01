import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/connectivity_notifier.dart';

/// Sticky banner when there is no network — does not block taps below (Material gap).
class OfflineModeBanner extends StatelessWidget {
  const OfflineModeBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ConnectivityNotifier>(
      builder: (context, net, _) {
        if (net.isOnline) return const SizedBox.shrink();
        return Material(
          color: Colors.transparent,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              border: Border(
                bottom: BorderSide(color: Colors.amber.shade300),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  Icon(Icons.wifi_off, size: 20, color: Colors.brown.shade700),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Offline Mode Active — data may be limited until you reconnect',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.brown.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
