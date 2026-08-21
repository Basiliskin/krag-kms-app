# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Krag** is a secure, local-first knowledge base (PKM/note-taking app) built with Flutter. It features:
- Block-based editor (AppFlowyEditor) similar to Notion
- End-to-end encryption with AES-GCM
- Google Drive sync with offline-first caching
- Tag-based organization and command palette (CMD+K)

## Development Commands

```bash
# Install dependencies
flutter pub get

# Run code generators (required after modifying Hive models, env vars, or JSON models)
flutter pub run build_runner build --delete-conflicting-outputs

# Run the app
flutter run -d macos    # Desktop (recommended for development)
flutter run -d chrome   # Web
flutter run             # Default device

# Run tests
flutter test                    # All tests
flutter test <path_to_file>     # Single test file

# Build release
flutter build macos --release
flutter build web --release
```

## Architecture

### Layers (Bottom to Top)
```
models/       →  Data types (Note, Tag, SearchResult, etc.)
services/     →  Business logic & external integrations (auth, sync, crypto)
stores/       →  Riverpod state management (Notifiers for auth, notes, tabs, keys)
ui/           →  Presentation layer (screens, components, editor)
```

### State Management: Riverpod 2.0
- **NotifierProvider** for complex state (auth, notes, tabs, keys)
- **FutureProvider** for async services (DriveSyncService)
- All providers defined in `lib/stores/providers.dart`

### Key State Stores
| Provider | State Class | Purpose |
|----------|-------------|---------|
| `authStoreProvider` | `AuthState` | Vault unlock, Google auth |
| `notesStoreProvider` | `NotesStateData` | Notes CRUD, sync status |
| `tabsStoreProvider` | `List<String>` | Open tabs |
| `keysStoreProvider` | `KeysState` | Encryption keys (DMK, salt) |

### Service Layer Pattern
- Services implement interfaces from `lib/services/interfaces.dart`
- Injected via Riverpod providers in `providers.dart`
- Key services: `GoogleAuthService`, `DriveAdapter`, `DriveSyncService`, `CryptoService`, `VaultKeyService`

## Security Architecture

- **KEK (Key Encryption Key):** Derived from password via PBKDF2 (600k iterations)
- **DMK (Data Master Key):** Randomly generated, wrapped by KEK
- **Content Encryption:** AES-256-GCM for note content
- **Web Auth:** PKCE flow for OAuth2 (bypasses FedCM issues)

## Data Storage

| Storage | Purpose |
|---------|---------|
| **Hive** | Local persistence (tags, notes cache) |
| **SharedPreferences** | Session data, sync metadata |
| **Google Drive** | Cloud sync (encrypted content) |
| **flutter_secure_storage** | Sensitive credentials |

## Key File Paths

- Entry: `lib/main.dart`
- Providers: `lib/stores/providers.dart`
- Auth: `lib/services/google_auth_service.dart`, `lib/stores/auth_store.dart`
- Notes/Sync: `lib/stores/notes_store.dart`, `lib/services/drive_sync_service.dart`
- Encryption: `lib/services/crypto_service.dart`, `lib/services/vault_key_service.dart`
- Editor: `lib/ui/editor/block_editor.dart`
- Constants: `lib/constants/index.dart`
- Types: `lib/types/index.dart`

## Conventions

- Services use interfaces from `lib/services/interfaces.dart`
- Dark theme: primary color `#FF6B00`, background `#121212`
- AppFlowyEditor for block-based content editing
- Web platform uses separate auth implementation with PKCE
