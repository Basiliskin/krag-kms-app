import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cryptography/cryptography.dart';

class KeysState {
  final SecretKey? dmk; // Data Master Key
  final Uint8List? salt; // Vault Salt

  const KeysState({this.dmk, this.salt});

  bool get hasKey => dmk != null;

  KeysState copyWith({
    SecretKey? dmk,
    Uint8List? salt,
  }) {
    return KeysState(
      dmk: dmk ?? this.dmk,
      salt: salt ?? this.salt,
    );
  }
}

class KeysNotifier extends Notifier<KeysState> {
  @override
  KeysState build() {
    return const KeysState();
  }

  void setKeys(SecretKey dmk, Uint8List salt) {
    state = state.copyWith(dmk: dmk, salt: salt);
  }

  void clearKeys() {
    state = const KeysState();
  }
}

final keysStoreProvider =
    NotifierProvider<KeysNotifier, KeysState>(KeysNotifier.new);
