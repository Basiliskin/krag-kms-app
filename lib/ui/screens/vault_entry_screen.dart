import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../stores/auth_store.dart';
import '../components/drive_connect_button.dart';
import '../components/loading_dialog.dart';

class VaultEntryScreen extends ConsumerStatefulWidget {
  const VaultEntryScreen({super.key});

  @override
  ConsumerState<VaultEntryScreen> createState() => _VaultEntryScreenState();
}

class _VaultEntryScreenState extends ConsumerState<VaultEntryScreen> {
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit(bool isNewVault) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);

    try {
      await ref.read(authStoreProvider.notifier).handleUnlock(
            _passwordController.text,
            isNewVault,
          );
    } catch (e) {
      // Error is handled in store
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStoreProvider);
    final isNewVault = authState.vaultSalt == null;
    final isConnected = authState.isGoogleDriveConnected;
    final isLoading =
        authState.isLoading || authState.isVerifyingDrive || _isSubmitting;
    final errorMessage = authState.error;

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 448),
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF3A3A3A)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        isNewVault
                            ? 'Create Your Secure Vault'
                            : 'Unlock Your Vault',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFEDEDED),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        isNewVault
                            ? 'Set a master password to encrypt your knowledge base. This password never leaves your device.'
                            : 'Enter your master password to decrypt your data.',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFFA0A0A0),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      if (!isConnected) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF121212),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF2A2A2A)),
                          ),
                          child: Column(
                            children: [
                              const Text(
                                'Not authenticated with Google Drive',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                isNewVault
                                    ? 'Please connect to Google Drive before creating your vault.'
                                    : 'Please connect to Google Drive to unlock your vault.',
                                style: const TextStyle(
                                  color: Color(0xFFA0A0A0),
                                  fontSize: 12,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              const DriveConnectButton(),
                            ],
                          ),
                        ),
                      ] else ...[
                        const DriveConnectButton(),
                      ],
                      const SizedBox(height: 24),
                      Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Master Password',
                              style: TextStyle(
                                color: Color(0xFFEDEDED),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _passwordController,
                              obscureText: true,
                              enabled: isConnected && !isLoading,
                              style: const TextStyle(color: Color(0xFFEDEDED)),
                              decoration: InputDecoration(
                                hintText: isNewVault
                                    ? 'Set a master password'
                                    : 'Enter master password',
                                hintStyle:
                                    const TextStyle(color: Color(0xFF4A4A4A)),
                                filled: true,
                                fillColor: const Color(0xFF121212),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: const BorderSide(
                                      color: Color(0xFF3A3A3A)),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Password is required';
                                }
                                if (isNewVault && value.length < 7) {
                                  return 'Password must be at least 7 characters';
                                }
                                return null;
                              },
                              onFieldSubmitted: (_) =>
                                  _handleSubmit(isNewVault),
                            ),
                            if (errorMessage != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color.fromRGBO(127, 29, 29, 0.2),
                                  border: Border.all(
                                      color: const Color.fromRGBO(
                                          185, 28, 28, 0.5)),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  errorMessage,
                                  style: const TextStyle(
                                      color: Colors.redAccent, fontSize: 13),
                                ),
                              ),
                            ],
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: (isConnected && !isLoading)
                                  ? () => _handleSubmit(isNewVault)
                                  : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFF6B00),
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                disabledBackgroundColor:
                                    const Color(0xFF2A2A2A),
                                disabledForegroundColor:
                                    const Color(0xFF6A6A6A),
                              ),
                              child: Text(
                                isNewVault ? 'Create Vault' : 'Unlock Vault',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (isConnected) ...[
                              const SizedBox(height: 16),
                              TextButton(
                                onPressed: () {
                                  _passwordController.clear();
                                  ref
                                      .read(authStoreProvider.notifier)
                                      .handleLogout();
                                },
                                child: const Text(
                                  'Disconnect / Change Account',
                                  style: TextStyle(
                                    color: Color(0xFFA0A0A0),
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            LoadingDialog(
              isOpen: isLoading,
              message: authState.isVerifyingDrive
                  ? 'Verifying Vault Structure...'
                  : 'Processing...',
            ),
          ],
        ),
      ),
    );
  }
}
