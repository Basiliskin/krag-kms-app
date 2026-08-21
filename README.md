# Krag — Secure, Local-First Knowledge Base

Krag is a block-based knowledge base (PKM / note-taking app) built with Flutter. Notes are composed in a
Notion-style block editor, organized with tags, labels, and a note hierarchy, and searched instantly from a
command palette. Everything is encrypted on-device before it leaves your device.

- **Master-password vault** — a password-derived key protects a random Data Master Key that encrypts all content.
- **Encrypted by default** — note content and the note index are AES-256-GCM encrypted client-side.
- **Offline-first** — notes are cached locally (encrypted) and work without a connection; the app re-hydrates
  and reconciles when you're back online.
- **Cross-platform** — runs on macOS, Windows, Linux, web, Android, and iOS.

## Features

- **Block-based editor** powered by [AppFlowyEditor](https://github.com/AppFlowy-IO/AppFlowyEditor) — paragraphs,
  headings, lists, task lists, code blocks with syntax highlighting, links, and inline styling.
- **Encrypted cloud sync** via Firebase — Google sign-in (Firebase Auth) and Cloud Firestore store only
  encrypted blobs, scoped per user.
- **Offline-first sync** — encrypted local cache, versioned notes, automatic hydration of stale/missing content,
  and orphan-file reconciliation.
- **Command palette** (`Cmd`/`Ctrl`+`K`) — instant note search over an encrypted local search index.
- **Organization** — tags, labels, note filters, a note hierarchy (parent/child), and open tabs.
- **Export** — export all notes as a ZIP of Markdown files.
- **Dark theme** — primary `#FF6B00` on `#121212`.

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Flutter / Dart (SDK `>=3.2.0`) |
| State management | Riverpod 3 |
| Editor | AppFlowyEditor (block-based) |
| Cryptography | `cryptography` — AES-256-GCM, PBKDF2 (SHA-256, 600k iterations) |
| Auth & sync | Firebase Auth (Google), Cloud Firestore |
| Local storage | Hive, SharedPreferences, `flutter_secure_storage` |

## Getting Started

### Prerequisites

- Flutter SDK `>=3.2.0`
- A Firebase project with **Authentication** (Google provider) and **Cloud Firestore** enabled
- Google OAuth credentials (`GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`)

### Setup

```bash
# 1. Install dependencies
flutter pub get

# 2. Run code generators (Hive adapters, JSON serializers, env)
dart run build_runner build --delete-conflicting-outputs

# 3. Configure environment variables
#    Create a .env file (gitignored) with:
#    GOOGLE_CLIENT_ID=...
#    GOOGLE_CLIENT_SECRET=...
```

Firebase configuration:

- Generate `lib/firebase_options.dart` for your project with the FlutterFire CLI:
  ```bash
  flutterfire configure
  ```
- Android only: place `google-services.json` in `android/app/` (see `docs/ANDROID_SETUP.md`).

### Run

```bash
flutter run -d macos    # Desktop (recommended for development)
flutter run -d chrome   # Web
flutter run             # Default device
```

### Test

```bash
flutter test
```

### Build release

```bash
flutter build macos --release
flutter build web --release
```

## First Run

1. **Sign in with Google.**
2. **Create your vault** by setting a master password (at least 7 characters). The password is used to derive an
   encryption key and is never stored or transmitted.
3. **Create notes** in the block editor and organize them with tags and labels.
4. Press **`Cmd`/`Ctrl` + `K`** to search notes.
5. Use the **Import / Export** dialog to export all notes as a ZIP of Markdown files.

## Security Model

Krag encrypts before it syncs — the cloud never receives plaintext note content.

```
Master password (never stored, never sent)
        │
        ▼
PBKDF2-SHA256 (600,000 iterations, per-vault random salt)
        │
        ▼
KEK (Key Encryption Key)
        │
        ▼  wraps
DMK (Data Master Key) — random 256-bit key per vault
        │
        ▼
AES-256-GCM — encrypts note content, the note index, and the search index
```

The wrapped DMK and salt are stored remotely (encrypted); the unwrapped DMK lives only in the current session.

## Project Structure

```
lib/
  models/     →  Data types (Note, Tag, ...)
  services/   →  Business logic & integrations (crypto, auth, sync, search)
  stores/     →  Riverpod state (auth, notes, tabs, keys)
  ui/         →  Screens, components, and the block editor
  utils/      →  Encoding, editor migration, logging
  constants/  →  App constants (storage keys, folder paths, theme)
  env/        →  Obfuscated environment configuration (envied)
```

Key files:

- Entry point: `lib/main.dart`
- Providers / DI: `lib/stores/providers.dart`
- Encryption: `lib/services/crypto_service.dart`, `lib/services/vault_key_service.dart`
- Sync: `lib/services/drive_sync_service.dart`, `lib/services/firestore_adapter.dart`
- Editor: `lib/ui/editor/block_editor.dart`
- Search palette: `lib/ui/components/command_palette.dart`

## Platforms

Android · iOS · Linux · macOS · Web · Windows

## Repository

https://github.com/Basiliskin/krag-kms-app

## License

Open-source. A license file has not been added yet.
