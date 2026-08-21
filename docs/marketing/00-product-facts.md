# Product Facts

> Single source of truth for all downstream marketing skills. No promotional material may claim more
> than this document supports.

## Verified facts

Every fact traced to a repository file, the README, or the user. The `source:` field is restricted to
`<repo-relative path>` | `README` | `user`.

- Cross-platform Flutter app named `krag_app` (v1.0.0+1), written in Dart — source: `pubspec.yaml`
- Ships platform targets for Android, iOS, Linux, macOS, web, and Windows — source: `android/`, `ios/`, `linux/`, `macos/`, `web/`, `windows/` (platform directories), `pubspec.yaml`
- Block-based note editor built on AppFlowyEditor (^6.2.0) — source: `pubspec.yaml`, `lib/ui/editor/block_editor.dart`
- Note content is encrypted with AES-256-GCM — source: `lib/services/crypto_service.dart` (`AesGcm.with256bits()`)
- A Key Encryption Key (KEK) is derived from the master password via PBKDF2 (SHA-256, 600,000 iterations) — source: `lib/services/crypto_service.dart`
- A random Data Master Key (DMK) is generated per vault and wrapped by the KEK — source: `lib/services/crypto_service.dart` (`generateDMK` / `wrapDMK`), `lib/services/vault_key_service.dart`
- Vault is created and unlocked with a master password; the setup UI states the password never leaves the device — source: `lib/ui/screens/vault_entry_screen.dart`
- Google sign-in via GoogleSignIn and Firebase Auth (Google provider) — source: `lib/services/google_auth_service.dart`, `lib/stores/providers.dart`
- Encrypted note content and the note index sync to Firebase Cloud Firestore, scoped per Firebase user — source: `lib/stores/providers.dart` (wires `FirestoreAdapter`), `lib/services/firestore_adapter.dart`, `lib/services/drive_sync_service.dart`
- A legacy Google Drive API adapter implements the same interface but is not wired into the app's providers (Firestore is the active sync backend) — source: `lib/services/drive_adapter.dart` (class never instantiated), `lib/stores/providers.dart`
- Offline-first design: notes are cached locally (encrypted) and re-hydrated from the remote when stale or missing — source: `lib/services/drive_sync_service.dart`, `lib/services/file_hydration_service.dart`
- Versioned notes with drift handling: dirty-note tracking, version-stagnation/regression checks, ghost-note cleanup, and orphan reconciliation — source: `lib/stores/notes_store.dart`, `lib/services/orphan_reconciliation_service.dart`
- Organization via tags (Hive-backed), labels, note filters, a note hierarchy (`parentId`), and open tabs — source: `lib/services/tag_service.dart`, `lib/services/label_service.dart`, `lib/types/index.dart`, `lib/ui/components/tag_sidebar.dart`, `lib/stores/tabs_store.dart`
- Command palette search opened with Cmd/Ctrl+K, backed by an encrypted local search index — source: `lib/ui/components/command_palette.dart`, `lib/services/search_service.dart`, `lib/constants/index.dart` (`StorageKeys.searchIndex = 'search_index_encrypted'`)
- Export all notes as a ZIP of Markdown files; Markdown import is stubbed as "Coming soon" — source: `lib/ui/components/import_export.dart`
- Editor content is migrated between HTML/TipTap and a normalized AppFlowy block format — source: `lib/utils/editor_migration_engine.dart`, `lib/stores/notes_store.dart`
- Dark theme with primary color `#FF6B00` on background `#121212` — source: `lib/main.dart`
- Uses Firebase infrastructure (Firebase Auth, Cloud Firestore), Firebase project `krag-2edd4` — source: `lib/firebase_options.dart`, `firebase.json`
- Automated tests exist for the editor migration engine (HTML → AppFlowy block conversion) — source: `test/editor_migration_engine_test.dart`

## Repository evidence

Concrete file paths in this repository that back the Verified facts.

- `pubspec.yaml`
- `lib/main.dart`
- `lib/stores/providers.dart`
- `lib/stores/auth_store.dart`
- `lib/stores/notes_store.dart`
- `lib/stores/tabs_store.dart`
- `lib/services/crypto_service.dart`
- `lib/services/vault_key_service.dart`
- `lib/services/google_auth_service.dart`
- `lib/services/firestore_adapter.dart`
- `lib/services/drive_adapter.dart`
- `lib/services/drive_sync_service.dart`
- `lib/services/file_hydration_service.dart`
- `lib/services/orphan_reconciliation_service.dart`
- `lib/services/index_manager.dart`
- `lib/services/search_service.dart`
- `lib/services/tag_service.dart`
- `lib/services/label_service.dart`
- `lib/types/index.dart`
- `lib/constants/index.dart`
- `lib/ui/screens/vault_entry_screen.dart`
- `lib/ui/components/command_palette.dart`
- `lib/ui/components/import_export.dart`
- `lib/ui/components/tag_sidebar.dart`
- `lib/ui/editor/block_editor.dart`
- `lib/utils/editor_migration_engine.dart`
- `test/editor_migration_engine_test.dart`
- `lib/firebase_options.dart`
- `firebase.json`
- `README.md` (stock Flutter boilerplate; contains no product claims)
- `notes.md` (developer scratch notes; references a past Surge staging deployment, not production)

## User-provided facts

Only the four non-derivable categories: production URL, primary goal, open-source status, features
not visible in the repository.

- Public presence / production URL: the project is published as the GitHub repository
  `https://github.com/Basiliskin/krag-kms-app`; no separate hosted web or app-store URL was provided.
- Primary goal: portfolio / skill-signal project (demonstrating the product and engineering, not
  driving mass adoption).
- Open-source status: public / open-source. No `LICENSE` file is present in the repo; the specific
  license is undetermined.
- Features not visible in the repository: none — the user confirmed the code is current.

## Unknown

Gaps recorded as open. Never invent an answer here.

- Number of active users.
- Performance benchmarks (e.g., editor load time, sync latency, vault-unlock time).
- Browser support matrix (the project is developed against Chrome via `flutter run -d chrome`; no
  formal support statement exists).
- Hosted deployment URL for the app itself (only the GitHub repository was provided).
- Specific open-source license (repo is public, but no `LICENSE` file is present).
- Markdown import: stubbed as "Coming soon" — no implementation or ETA in the codebase.
- Existence of subscription/paywall features: build flags referenced in `notes.md` suggest they were
  considered, but no subscription code exists in `lib/` or `pubspec.yaml`.

## Forbidden assumptions

Never claim the following without explicit evidence. Un-evidenced occurrences are parked here, not in
Verified facts.

- fastest
- most secure
- better than competitors
- privacy-preserving
