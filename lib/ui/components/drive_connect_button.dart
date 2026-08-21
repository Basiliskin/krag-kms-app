import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../stores/auth_store.dart';

class DriveConnectButton extends ConsumerWidget {
  const DriveConnectButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStoreProvider);
    final isConnected = authState.isGoogleDriveConnected;

    // improved loading state to be less jarring during redirect preparation
    final isRedirecting = authState.isLoading && !authState.isVerifyingDrive;

    if (isRedirecting) {
      return ElevatedButton.icon(
        onPressed: null, // Disable button while redirecting
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.grey[200],
          foregroundColor: Colors.black54,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          minimumSize: const Size(200, 45),
        ),
        icon: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.black54),
          ),
        ),
        label: const Text('Redirecting to Google...'),
      );
    }

    if (isConnected) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color.fromRGBO(20, 83, 45, 0.2),
          border: Border.all(color: const Color.fromRGBO(21, 128, 61, 0.5)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF4ADE80), size: 20),
            const SizedBox(width: 8),
            const Text(
              'Drive Connected',
              style: TextStyle(
                  color: Color(0xFF4ADE80), fontWeight: FontWeight.w500),
            ),
            const SizedBox(width: 12),
            InkWell(
              onTap: () => ref.read(authStoreProvider.notifier).handleLogout(),
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(4.0),
                child: Icon(Icons.logout, color: Colors.red[400], size: 18),
              ),
            ),
          ],
        ),
      );
    }

    return ElevatedButton.icon(
      onPressed: () {
        // This triggers the full page redirect flow (PKCE)
        ref.read(authStoreProvider.notifier).signInWithGoogle();
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        minimumSize: const Size(200, 45),
      ),
      icon: const Icon(Icons.add_to_drive, color: Colors.black87, size: 20),
      label: const Text('Connect Google Drive'),
    );
  }
}
