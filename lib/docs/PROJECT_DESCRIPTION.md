# Krag - Project Description for Dart/Flutter Migration

## Executive Summary

**Krag** is a privacy-centric, local-first knowledge management application that combines Notion-style block-based editing with Obsidian-style graph-based knowledge linking. The application implements zero-knowledge encryption, ensuring all data is encrypted client-side before being stored in Google Drive. Google Drive acts purely as encrypted storage - it never has access to plaintext data.

**Current Stack:** React 19 + TypeScript, TipTap (ProseMirror), MobX, Tailwind CSS  
**Target Stack:** Dart/Flutter

---

## 1. Core Architecture

### 1.1 High-Level Architecture

The application follows a **local-first architecture** with the following principles:
- All operations work offline
- Google Drive is used as encrypted backup storage only
- Zero-knowledge encryption (Google never sees plaintext)
- Session-based security (keys cleared on app close)
- Index-based lazy loading (metadata first, content on-demand)

### 1.2 Data Flow Architecture

```
User Password (never stored)
 ↓ PBKDF2 (600k iterations, SHA-256)
KEK (Key Encryption Key) - derived from password + salt
 ↓ AES-KW (Key Wrapping)
DMK (Data Master Key) - stored encrypted in Drive as wrapped_keys.json
 ↓ AES-GCM encryption (authenticated encryption)
Actual Data (notes, index, search index)
```

### 1.3 Storage Hierarchy

**Session Storage (Volatile):**
- DMK (Data Master Key) - cleared on tab/app close
- Stored as CryptoKey ↔ base64 conversion

**Local Storage (Persistent):**
- Salt (base64-encoded)
- Google Drive OAuth tokens
- Folder path cache (folder ID mappings)
- User preferences (tags, labels, filters)
- Vault configuration metadata

**IndexedDB (Persistent):**
- Encrypted search index (FlexSearch Document index)
- Key-value store for encrypted data

**Google Drive (Cloud Storage):**
- Encrypted vault data
- Folder structure: `krag-vault/config/` and `krag-vault/docs/`

---

## 2. Core Features

### 2.1 Note Management
- **CRUD Operations:** Create, read, update, delete notes
- **Hierarchical Notes:** Parent-child relationships (parentId field)
- **Lazy Loading:** Index loaded first, content loaded on-demand
- **Version Control:** Each note has `_v` (version) field for conflict detection
- **Metadata:** Title, content, tags, labels, modifiedTime, parentId

### 2.2 Rich Text Editing
- **Block-Based Editor:** TipTap (ProseMirror) integration
- **Features:**
  - Paragraphs, headings (H1-H6)
  - Bold, italic, code, strikethrough
  - Code blocks with syntax highlighting (Prism.js, 40+ languages)
  - Task lists (checkboxes)
  - Highlighting
  - Placeholder text
  - Slash commands (`/` menu)
  - Block menu (drag handles)
- **Content Format:** HTML string stored in note.content

### 2.3 Organization & Discovery
- **Tags:** Color-coded tags with custom colors
- **Labels:** Simple string labels
- **Search:** Full-text search with FlexSearch
  - Tag-specific search (`#tagname`)
  - Label-specific search (`@labelname`)
  - Content search
- **Filtering:** Filter notes by tags, labels, or combinations
- **Graph View:** Visual graph of note relationships (parent-child links)
- **Command Palette:** Cmd+K search interface

### 2.4 Synchronization
- **Bidirectional Sync:** Local ↔ Google Drive
- **Conflict Resolution:** Last-write-wins based on modifiedTime
- **Version Checking:** Prevents overwriting newer versions
- **Index-Based:** Encrypted index.json lists all notes (metadata only)
- **Mutex Protection:** Prevents race conditions on index updates

### 2.5 Security & Encryption
- **Zero-Knowledge:** All encryption happens client-side
- **Key Hierarchy:** Password → KEK → DMK → Data
- **Session-Based:** DMK only in volatile memory/session storage
- **Authenticated Encryption:** AES-GCM (encryption + authentication)
- **Key Wrapping:** AES-KW for wrapping/unwrapping DMK

---

## 3. Data Models

### 3.1 Note
```typescript
interface Note {
  id: string;                    // UUID or generated ID
  title: string;                 // Note title
  content: string;               // HTML content from TipTap
  tags: string[];                // Array of tag names
  labels: string[];              // Array of label names
  parentId?: string;             // Optional parent note ID
  modifiedTime?: string;         // ISO 8601 timestamp
  _v?: number;                   // Version number for conflict detection
}
```

### 3.2 Note Index Entry
```typescript
interface NoteIndexEntry {
  id: string;
  title: string;
  tags: string[];
  labels: string[];
  modifiedTime: string;
  parentId?: string;
  _v?: number;
}
```

### 3.3 Tag
```typescript
interface Tag {
  name: string;
  color: string;  // Hex color code (e.g., "#3b82f6")
}
```

### 3.4 Search Result
```typescript
interface SearchResult {
  id: string;
  title: string;
}
```

### 3.5 Graph Data
```typescript
interface GraphNode {
  id: string;
  name: string;
}

interface GraphLink {
  source: string;  // Parent note ID
  target: string; // Child note ID
}

interface GraphData {
  nodes: GraphNode[];
  links: GraphLink[];
}
```

### 3.6 Note Filters
```typescript
interface NoteFilters {
  tags: string[];      // Filter by these tags (AND logic)
  labels: string[];    // Filter by these labels (AND logic)
}
```

---

## 4. Services & Business Logic

### 4.1 CryptoService
**Purpose:** All cryptographic operations using Web Crypto API

**Key Methods:**
- `generateSalt(): Uint8Array` - Generate 16-byte random salt
- `deriveKey(password: string, salt: Uint8Array): Promise<CryptoKey>` - PBKDF2 key derivation (600k iterations, SHA-256)
- `encrypt(key: CryptoKey, plaintext: string): Promise<{iv: Uint8Array, cipherText: ArrayBuffer}>` - AES-GCM encryption
- `decrypt(key: CryptoKey, iv: Uint8Array, cipherText: ArrayBuffer): Promise<string>` - AES-GCM decryption
- `encryptBinary(key: CryptoKey, data: Uint8Array): Promise<{iv: Uint8Array, encrypted: Uint8Array}>` - Binary encryption
- `decryptBinary(key: CryptoKey, iv: Uint8Array, encrypted: Uint8Array): Promise<Uint8Array>` - Binary decryption
- `generateDMK(): Promise<CryptoKey>` - Generate 256-bit Data Master Key
- `wrapDMK(kek: CryptoKey, dmk: CryptoKey): Promise<{iv: Uint8Array, wrappedKey: string}>` - Wrap DMK with KEK (AES-KW)
- `unwrapDMK(kek: CryptoKey, iv: Uint8Array, wrappedKey: string): Promise<CryptoKey>` - Unwrap DMK
- `computeHash(data: Uint8Array): Promise<string>` - SHA-256 hash for content verification

**Critical Details:**
- Uses AES-GCM with 12-byte IVs
- Safari compatibility: Creates explicit ArrayBuffer copies (not views)
- All keys are extractable for wrapping/unwrapping

### 4.2 VaultKeyService
**Purpose:** Vault initialization and unlock operations

**Key Methods:**
- `vaultExists(): Promise<boolean>` - Check if vault is initialized
- `initializeVault(password: string): Promise<{salt, kek, dmk, wrappedKeysTimestamp}>` - Create new vault
  - Generates salt, derives KEK, generates DMK
  - Creates `salt.json` and `wrapped_keys.json` in Drive
- `unlockVault(password: string, storedSalt?: Uint8Array): Promise<{salt, kek, dmk, wrappedKeysTimestamp}>` - Unlock existing vault
  - Retrieves salt from Drive (or uses storedSalt fallback)
  - Derives KEK, unwraps DMK
  - Handles missing files gracefully (recreates if needed)
- `getSalt(): Promise<Uint8Array | null>` - Get salt from Drive

**File Structure:**
- `salt.json`: `{salt: "base64-encoded-salt"}` (unencrypted)
- `wrapped_keys.json`: `{iv: "base64-iv", wrappedKey: "base64-wrapped-dmk"}` (encrypted with KEK)

### 4.3 DriveSyncService
**Purpose:** Core sync engine between local state and Google Drive

**Key Methods:**
- `initialize(dataMasterKey: CryptoKey): Promise<void>` - Initialize sync service
- `saveNote(note: Note, localNote?: Note | null): Promise<Note>` - Save note to Drive
  - Version checking (throws VERSION_MISMATCH if local version != remote version)
  - Increments version on save
  - Updates parent note if note has parentId
  - Saves note file and updates index in parallel
- `loadNote(noteId: string, localNote?: Note | null): Promise<Note | null>` - Load note from Drive
  - Uses cached file ID if available
  - Returns local note if versions match (optimization)
  - Lazy loads content
- `deleteNote(noteId: string): Promise<void>` - Delete note from Drive
  - Updates parent note if note has parentId
  - Removes from index
- `loadIndex(): Promise<NoteIndexEntry[]>` - Load encrypted index.json
- `syncNotes(localNotes: Record<string, Note>): Promise<Record<string, Note>>` - Full bidirectional sync
  - Compares local vs remote by modifiedTime
  - Pulls newer remote notes
  - Pushes newer local notes
  - Handles conflicts (last-write-wins)

**Index Management:**
- Index stored as encrypted JSON array in `config/index.json`
- Mutex-protected updates to prevent race conditions
- Index contains metadata only (no content)

**Compression:**
- Notes compressed with gzip before encryption (if > threshold)
- Backward compatible (handles uncompressed notes)

### 4.4 DriveAdapter
**Purpose:** Low-level Google Drive API wrapper

**Key Methods:**
- `getFolderIdByPath(path: string): Promise<string>` - Resolve folder by path (with caching)
- `listFiles(folderId: string, useCache?: boolean): Promise<DriveFileMetadata[]>` - List files in folder
- `getFile(fileId: string): Promise<Uint8Array>` - Download file content
- `getFileMetadata(fileId: string): Promise<DriveFileMetadata>` - Get file metadata
- `createFile(name: string, data: Uint8Array, mimeType: string, parentId: string): Promise<string>` - Create file
- `ensureFile(name: string, data: Uint8Array, mimeType: string, folderPath: string, version?: number): Promise<string>` - Create or update file
- `trashFile(fileId: string): Promise<void>` - Delete file (move to trash)
- `verifyRootFolder(path: string): Promise<boolean>` - Verify folder exists and is valid

**Caching Strategy:**
- Folder path → ID cache in localStorage
- File list cache (30-second TTL)
- File ID cache by note ID
- Prevents excessive API calls

**Folder Structure:**
```
krag-vault/                    (root folder)
├── config/                    (configuration folder)
│   ├── salt.json             (unencrypted salt)
│   ├── wrapped_keys.json     (encrypted DMK)
│   └── index.json            (encrypted note index)
└── docs/                      (documents folder)
    ├── {note-id-1}.bin       (encrypted note content)
    └── {note-id-2}.bin       (encrypted note content)
```

**Duplicate Detection:**
- Detects duplicate folders/files by name
- Resolves conflicts by selecting most recent

### 4.5 GoogleAuthService
**Purpose:** OAuth 2.0 authentication with PKCE

**Key Methods:**
- `generateCodeVerifier(): string` - Generate PKCE code verifier
- `generateCodeChallenge(verifier: string): Promise<string>` - Generate SHA-256 code challenge
- `getAuthUrl(clientId: string, redirectUri: string): Promise<string>` - Get OAuth authorization URL
- `handleCallback(code: string, clientId: string, redirectUri: string): Promise<void>` - Exchange code for tokens
- `isAuthenticated(): boolean` - Check if user is authenticated
- `getToken(): string | null` - Get access token
- `refreshAccessToken(): Promise<string>` - Refresh expired token
- `clearTokens(): void` - Clear stored tokens

**OAuth Flow:**
- PKCE (Proof Key for Code Exchange) for security
- Scope: `https://www.googleapis.com/auth/drive.file` (app-created files only)
- Tokens stored in localStorage
- Auto-refresh on 401 errors

### 4.6 SearchService
**Purpose:** Full-text search with FlexSearch

**Key Methods:**
- `initialize(): Promise<void>` - Load encrypted index from IndexedDB
- `indexNote(noteId: string, content: string, tags: string[], labels: string[]): Promise<void>` - Index a note
- `removeNote(noteId: string): Promise<void>` - Remove note from index
- `search(query: string): Promise<string[]>` - Search and return note IDs
  - Tag search: `#tagname` searches only tags field
  - Label search: `@labelname` searches only labels field
  - General search: searches content, tags, labels
- `saveIndex(key?: CryptoKey): Promise<void>` - Save encrypted index to IndexedDB
- `loadIndex(key?: CryptoKey): Promise<void>` - Load encrypted index
- `forceSave(): Promise<void>` - Immediately save (bypass debounce)

**Index Structure:**
- FlexSearch Document index
- Fields: `id`, `content`, `tags`, `labels`
- Encrypted and stored in IndexedDB
- Auto-save with 5-second debounce

### 4.7 SessionService
**Purpose:** DMK session management

**Key Methods:**
- `storeDMKInSession(dmk: CryptoKey): Promise<void>` - Store DMK in sessionStorage
- `loadDMKFromSession(): Promise<CryptoKey | null>` - Load DMK from sessionStorage
- `clearDMKSession(): void` - Clear DMK from session

**Storage Format:**
- CryptoKey ↔ base64 conversion
- Stored in sessionStorage (cleared on tab close)

### 4.8 TagService
**Purpose:** Tag management (colors, CRUD)

**Key Methods:**
- `getTags(): Tag[]` - Get all tags
- `createTag(name: string, color: string): void` - Create tag
- `renameTag(oldName: string, newName: string): void` - Rename tag
- `setTagColor(name: string, color: string): void` - Set tag color
- `deleteTag(name: string): void` - Delete tag

**Storage:** Tags stored in localStorage

### 4.9 LabelService
**Purpose:** Label management

**Key Methods:**
- `getLabels(): string[]` - Get all labels
- `addLabel(label: string): void` - Add label
- `removeLabel(label: string): void` - Remove label

**Storage:** Labels stored in localStorage

---

## 5. UI Components

### 5.1 Main Layout Components

**App.tsx**
- Root component with provider hierarchy
- Handles authentication state
- Manages global UI state (modals, sidebars, command palette)

**MainContent.tsx**
- Primary layout wrapper
- Contains sidebar and editor area
- Handles responsive layout

**TagSidebar.tsx**
- Left sidebar navigation
- Note list with hierarchy
- Tag/label filtering UI
- Note creation/deletion
- Import/export functionality
- Graph view toggle

**BlockEditor.tsx**
- Main editor container
- Title input
- Tag/label badges
- Save button with sync status
- Copy to clipboard FAB
- Tags/Labels modal integration

**Editor.tsx**
- TipTap (ProseMirror) integration
- Rich text editing
- Slash commands (`/`)
- Block menu (drag handles)
- Code block language selector
- Syntax highlighting (Prism.js)

### 5.2 Modal Components

**CommandPalette.tsx**
- Cmd+K search interface
- Search results display
- Keyboard navigation

**TagsLabelsModal.tsx**
- Tag/label management UI
- Add/remove tags and labels
- Create new tags/labels

**TagModal.tsx**
- Edit tag name and color
- Delete tag

**UnlockPromptModal.tsx**
- Password input for vault unlock
- Error display

**LoadingDialog.tsx**
- Loading state overlay
- Progress messages

### 5.3 View Components

**GraphView.tsx**
- Force-directed graph visualization
- Shows parent-child relationships
- Interactive node selection

**Dashboard.tsx**
- Overview dashboard (if implemented)

**NoteList.tsx**
- Hierarchical note list
- Drag-and-drop support
- Context menu

### 5.4 Utility Components

**Toast.tsx**
- Success/error notifications
- Auto-dismiss

**VaultEntry.tsx**
- Vault unlock/create UI
- Google Drive connection

**LandingPage.tsx**
- First-time user onboarding

---

## 6. State Management

### 6.1 Context Architecture

**AuthContext (AuthProvider)**
- Vault unlock/lock state
- Google Drive connection status
- DMK session management
- Gates all authenticated features

**NotesContext (NotesProvider)**
- Note CRUD operations
- Current note selection
- Lazy loading coordination
- Delegates to DriveSyncService for persistence

### 6.2 MobX Stores

**DriveAuthStore**
- Authentication state
- Google Drive connection
- Vault state management

**NotesStore**
- Notes state (Record<string, Note>)
- Current note ID
- CRUD operations
- Sync coordination

### 6.3 Custom Hooks

**useAuth**
- Authentication operations
- Vault unlock/lock
- Google Drive connection

**useNotes**
- Note CRUD operations
- Current note management
- Sync operations

**useDriveSync**
- Drive sync initialization
- Sync operations
- Error handling

**useCommandPalette**
- Search functionality
- Command palette state

**useNoteTags**
- Tag operations on notes

**useNoteLabels**
- Label operations on notes

**useSearchIndexing**
- Auto-index notes on change

**useNoteFiltering**
- Filter notes by tags/labels

---

## 7. Security Model

### 7.1 Encryption Flow

1. **Vault Initialization:**
   - User provides password
   - Generate random salt (16 bytes)
   - Derive KEK: `PBKDF2(password, salt, 600000 iterations, SHA-256)`
   - Generate DMK: `AES-GCM 256-bit key`
   - Wrap DMK: `AES-KW(KEK, DMK)` → wrapped_keys.json
   - Store salt.json (unencrypted) and wrapped_keys.json in Drive

2. **Vault Unlock:**
   - User provides password
   - Load salt from Drive (or localStorage fallback)
   - Derive KEK: `PBKDF2(password, salt, 600000 iterations, SHA-256)`
   - Load wrapped_keys.json from Drive
   - Unwrap DMK: `AES-KW-unwrap(KEK, wrapped_keys.json)`
   - Store DMK in sessionStorage (volatile)

3. **Data Encryption:**
   - For each note/index/search index:
     - Generate random IV (12 bytes)
     - Encrypt: `AES-GCM-encrypt(DMK, IV, data)` → `{IV || encrypted_data}`
     - Store encrypted blob in Drive

4. **Data Decryption:**
   - Load encrypted blob from Drive
   - Extract IV (first 12 bytes)
   - Decrypt: `AES-GCM-decrypt(DMK, IV, encrypted_data)`
   - Return plaintext

### 7.2 Key Storage

- **Password:** Never stored
- **Salt:** Stored in Drive (salt.json) and localStorage (backup)
- **KEK:** Derived on-demand, never stored
- **DMK:** Stored encrypted in Drive (wrapped_keys.json), unwrapped and stored in sessionStorage during session
- **Session DMK:** Cleared on tab/app close

### 7.3 Security Guarantees

- **Zero-Knowledge:** Google Drive never sees plaintext
- **Authenticated Encryption:** AES-GCM provides encryption + authentication
- **Unique IVs:** Every encryption uses a new random IV
- **Key Derivation:** PBKDF2 with 600k iterations (resistant to brute force)
- **Session Security:** DMK cleared on app close

---

## 8. Storage Mechanisms

### 8.1 Browser Storage

**sessionStorage:**
- DMK (CryptoKey ↔ base64)
- Cleared on tab close

**localStorage:**
- Salt (base64)
- Google Drive OAuth tokens
- Folder path cache
- Tags and labels
- User preferences (filters, view settings)
- Vault configuration metadata

**IndexedDB:**
- Encrypted search index (FlexSearch Document)
- Key-value store via `idb` library

### 8.2 Google Drive Storage

**Folder Structure:**
```
krag-vault/
├── config/
│   ├── salt.json              (unencrypted JSON)
│   ├── wrapped_keys.json      (encrypted JSON)
│   └── index.json             (encrypted JSON array)
└── docs/
    ├── {note-id-1}.bin        (encrypted binary)
    └── {note-id-2}.bin        (encrypted binary)
```

**File Naming:**
- Notes: `{note-id}.bin` (e.g., `abc123.bin`)
- Config files: `salt.json`, `wrapped_keys.json`, `index.json`

**MIME Types:**
- Notes: `application/octet-stream`
- Config: `application/json`

**Version Control:**
- Each file has `_v` (version) field in metadata
- Incremented on every update
- Used for conflict detection

---

## 9. API Integrations

### 9.1 Google Drive API

**Base URL:** `https://www.googleapis.com/drive/v3`

**Endpoints Used:**
- `GET /files/{fileId}` - Get file metadata
- `GET /files/{fileId}?alt=media` - Download file content
- `POST /files` - Create file
- `PATCH /files/{fileId}` - Update file metadata
- `POST /files/{fileId}?uploadType=multipart` - Upload file
- `DELETE /files/{fileId}` - Delete file (trash)
- `GET /files?q=...` - List files with query

**Authentication:**
- OAuth 2.0 with PKCE
- Bearer token in Authorization header
- Auto-refresh on 401 errors

**Rate Limiting:**
- No explicit rate limiting implemented
- Caching reduces API calls

### 9.2 Google OAuth 2.0

**Authorization URL:** `https://accounts.google.com/o/oauth2/v2/auth`

**Token URL:** `https://oauth2.googleapis.com/token`

**Flow:**
1. Generate PKCE code verifier and challenge
2. Redirect user to authorization URL
3. User authorizes → redirect with code
4. Exchange code for tokens (with code_verifier)
5. Store tokens in localStorage
6. Use access_token for API calls
7. Refresh token when access_token expires

---

## 10. Key Dependencies & Technologies

### 10.1 Core Dependencies

**React 19**
- UI framework
- Hooks-based architecture

**TypeScript**
- Type safety
- Interface definitions

**TipTap (ProseMirror)**
- Rich text editor
- Block-based editing
- Extensions: StarterKit, TaskList, CodeBlock, Placeholder, Highlight

**MobX**
- State management
- Observable stores
- Reactive updates

**Tailwind CSS 4**
- Utility-first styling
- Dark theme (`#121212` background, `#EDEDED` text)

### 10.2 Cryptography

**Web Crypto API**
- Native browser crypto
- PBKDF2, AES-GCM, AES-KW, SHA-256
- CryptoKey management

### 10.3 Storage

**idb**
- IndexedDB wrapper
- Promise-based API

**localStorage / sessionStorage**
- Browser storage APIs

### 10.4 Search

**FlexSearch**
- Full-text search engine
- Document index
- Client-side only

### 10.5 Code Highlighting

**Prism.js**
- Syntax highlighting
- 40+ language support
- Theme: `prism-tomorrow`

### 10.6 Build & Development

**Vite**
- Build tool
- HMR (Hot Module Replacement)
- PWA plugin

**Vitest**
- Test framework
- jsdom environment

**ESLint**
- Linting

---

## 11. Migration Considerations for Dart/Flutter

### 11.1 Cryptography

**Current:** Web Crypto API (browser-native)

**Flutter Equivalent:**
- `crypto` package for hashing (SHA-256)
- `pointycastle` package for AES-GCM, AES-KW, PBKDF2
- `flutter_secure_storage` for secure key storage (equivalent to sessionStorage)

**Key Migration Points:**
- PBKDF2: 600k iterations, SHA-256, 256-bit output
- AES-GCM: 256-bit key, 12-byte IV
- AES-KW: For wrapping/unwrapping DMK
- Key derivation must match exactly (same salt → same KEK)

### 11.2 Storage

**Current:** localStorage, sessionStorage, IndexedDB

**Flutter Equivalent:**
- `shared_preferences` for localStorage equivalent
- `flutter_secure_storage` for sessionStorage equivalent (secure key storage)
- `sqflite` or `hive` for IndexedDB equivalent (search index storage)
- `path_provider` for file system access

**Migration Considerations:**
- Need to migrate existing data from browser storage
- Search index format may need conversion (FlexSearch → Flutter equivalent)

### 11.3 Rich Text Editor

**Current:** TipTap (ProseMirror)

**Flutter Equivalent:**
- `flutter_quill` - Rich text editor with similar features
- `super_editor` - More advanced block-based editor
- Custom implementation using `TextEditingController` and `WidgetSpan`

**Migration Considerations:**
- HTML content format may need conversion
- Block-based editing paradigm needs reimplementation
- Slash commands need custom implementation

### 11.4 State Management

**Current:** MobX + React Context

**Flutter Equivalent:**
- `provider` or `riverpod` for state management
- `mobx` package exists for Flutter (similar API)
- `flutter_bloc` for BLoC pattern

**Migration Considerations:**
- MobX Flutter package has similar API
- Context pattern maps to Provider/Riverpod

### 11.5 Google Drive API

**Current:** Fetch API with manual OAuth

**Flutter Equivalent:**
- `googleapis` package for Drive API
- `google_sign_in` package for OAuth
- `http` package for API calls

**Migration Considerations:**
- OAuth flow similar but Flutter-specific
- File upload/download logic needs adaptation
- Folder path resolution logic can be reused

### 11.6 Search

**Current:** FlexSearch

**Flutter Equivalent:**
- `flutter_search` or custom implementation
- `sqlite` with FTS (Full-Text Search) extension
- Custom search implementation using Dart collections

**Migration Considerations:**
- Search index format needs migration
- Tag/label search logic needs reimplementation

### 11.7 UI Components

**Current:** React components with Tailwind CSS

**Flutter Equivalent:**
- Material Design or Cupertino widgets
- Custom widgets for dark theme
- Responsive layout with `LayoutBuilder` / `MediaQuery`

**Migration Considerations:**
- Design system needs reimplementation
- Dark theme colors need mapping
- Responsive breakpoints need adaptation

### 11.8 Code Highlighting

**Current:** Prism.js

**Flutter Equivalent:**
- `flutter_highlight` package
- `highlight` package (Dart port of highlight.js)
- Custom syntax highlighting

**Migration Considerations:**
- Language support may differ
- Theme needs reimplementation

### 11.9 Platform-Specific Considerations

**Mobile:**
- Background sync (when app is backgrounded)
- Push notifications for sync status
- File system access for local caching
- Biometric authentication for vault unlock

**Desktop:**
- File system access for local vault (optional)
- Native menus and shortcuts
- Window management

**Web:**
- Similar to current implementation
- Service Worker for offline support
- PWA capabilities

---

## 12. Critical Implementation Details

### 12.1 Version Conflict Detection

When saving a note:
1. Load remote version from Drive metadata
2. Compare with local version
3. If mismatch: throw `VERSION_MISMATCH` error
4. User must sync first to resolve conflicts

### 12.2 Index Update Mutex

Index updates are mutex-protected to prevent race conditions:
```typescript
private acquireIndexLock(): Promise<() => void> {
  // Ensures only one index update at a time
}
```

### 12.3 Lazy Loading Strategy

1. Load index.json on app start (metadata only)
2. Display note list from index
3. Load note content on-demand when user selects note
4. Cache loaded content in memory

### 12.4 Compression

- Notes compressed with gzip before encryption (if > threshold)
- Compression happens before encryption (encrypted data doesn't compress)
- Backward compatible: handles uncompressed notes

### 12.5 Parent-Child Note Updates

When saving/deleting a child note:
- Parent note's `modifiedTime` is updated
- Parent note's version is incremented
- Parent note is saved to Drive

### 12.6 Search Index Auto-Save

- Index saved automatically 5 seconds after last change
- Force save on app unload/visibility change
- Encrypted with DMK before storage

### 12.7 Folder Path Resolution

- Paths resolved by name (not ID)
- Cached in localStorage to reduce API calls
- Handles duplicate folders (selects most recent)

### 12.8 Error Handling

**Common Errors:**
- `VERSION_MISMATCH`: Local version != remote version
- `WRAPPED_KEYS_MISSING`: Vault not unlocked
- `Decryption failed`: Wrong password or corrupted data
- `Authentication expired`: OAuth token expired
- `Network error`: API call failed

**Error Recovery:**
- Retry with exponential backoff
- Show user-friendly error messages
- Preserve local changes on sync failure

---

## 13. Testing Strategy

### 13.1 Test Coverage

**Services:**
- CryptoService: Encryption/decryption, key derivation
- DriveSyncService: Sync logic, conflict resolution
- SearchService: Indexing, search queries
- VaultKeyService: Vault initialization, unlock

**Components:**
- Editor: Content editing, block operations
- TagSidebar: Note list, filtering
- CommandPalette: Search, navigation

**Integration:**
- End-to-end sync flow
- Authentication flow
- Vault unlock flow

### 13.2 Test Tools

- **Vitest:** Test framework
- **Testing Library:** Component testing
- **fake-indexeddb:** IndexedDB mocking
- **Manual mocks:** Google Drive API mocking

---

## 14. Performance Considerations

### 14.1 Optimization Strategies

**Caching:**
- Folder path → ID cache
- File list cache (30-second TTL)
- File ID cache by note ID
- Loaded note content in memory

**Lazy Loading:**
- Index loaded first (metadata only)
- Content loaded on-demand
- Search index loaded on initialization

**Parallel Operations:**
- Note file and index updates in parallel
- Multiple file uploads in parallel during sync

**Compression:**
- Gzip compression before encryption
- Reduces storage and transfer size

### 14.2 Bottlenecks

**Google Drive API:**
- Rate limiting (not explicitly handled)
- Network latency
- Large file uploads/downloads

**Encryption:**
- PBKDF2 key derivation (600k iterations) - slow by design
- Large note encryption/decryption

**Search Index:**
- Large index serialization
- Index rebuild on app start

---

## 15. Future Enhancements (Not Implemented)

### 15.1 Planned Features

- Real-time multi-device sync (currently last-write-wins)
- Collaborative editing (CRDT-based, simplified from original spec)
- Append-only logs for audit trail
- Conflict resolution UI (currently automatic)

### 15.2 Limitations

- Single-writer assumption
- No real-time sync (manual sync required)
- No collaborative editing
- Last-write-wins conflict resolution (no merge)

---

## 16. Migration Checklist

### 16.1 Core Services
- [ ] CryptoService → Dart crypto implementation
- [ ] VaultKeyService → Flutter secure storage
- [ ] DriveSyncService → Google Drive API integration
- [ ] DriveAdapter → Google Drive API wrapper
- [ ] GoogleAuthService → OAuth 2.0 flow
- [ ] SearchService → Search implementation
- [ ] SessionService → Secure storage

### 16.2 UI Components
- [ ] Rich text editor (TipTap → Flutter equivalent)
- [ ] Note list with hierarchy
- [ ] Tag/label management
- [ ] Command palette
- [ ] Graph view
- [ ] Modals and dialogs

### 16.3 State Management
- [ ] Auth context/provider
- [ ] Notes context/provider
- [ ] MobX stores (or Flutter equivalent)

### 16.4 Storage Migration
- [ ] localStorage → shared_preferences
- [ ] sessionStorage → flutter_secure_storage
- [ ] IndexedDB → sqflite/hive
- [ ] Search index migration

### 16.5 Testing
- [ ] Unit tests for services
- [ ] Widget tests for components
- [ ] Integration tests for sync flow

---

## 17. Constants & Configuration

### 17.1 Key Constants

**PBKDF2:**
- Iterations: 600,000
- Hash: SHA-256
- Key length: 256 bits

**AES-GCM:**
- Key length: 256 bits
- IV length: 12 bytes
- Tag length: 16 bytes (automatic)

**Storage Keys:**
- `google_drive_tokens`
- `vault_salt`
- `wrapped_keys_timestamp`
- `search_index_encrypted`
- `drive_folder_path_cache`

**Folder Paths:**
- Root: `krag-vault`
- Config: `krag-vault/config`
- Docs: `krag-vault/docs`

**File Names:**
- `salt.json`
- `wrapped_keys.json`
- `index.json`
- Note files: `{note-id}.bin`

### 17.2 Environment Variables

- `VITE_GOOGLE_CLIENT_ID` - Google OAuth client ID
- `VITE_GOOGLE_CLIENT_SECRET` - Google OAuth client secret (optional)

---

## 18. Additional Notes

### 18.1 Design Philosophy

- **Local-first:** All operations work offline
- **Zero-knowledge:** Google never sees plaintext
- **Privacy-centric:** User controls all data
- **Simple sync:** Last-write-wins (no complex CRDT)

### 18.2 Browser Compatibility

- Safari compatibility: Explicit ArrayBuffer copies (not views)
- Chrome/Firefox: Standard Web Crypto API
- Edge: Same as Chrome

### 18.3 Security Best Practices

- Never store password
- DMK only in volatile memory
- Unique IV for every encryption
- Authenticated encryption (AES-GCM)
- PKCE for OAuth security

---

## Conclusion

This document provides a comprehensive overview of the Krag application architecture, features, and implementation details. Use this as a reference for migrating the application to Dart/Flutter, ensuring all security, functionality, and user experience aspects are preserved in the new implementation.
