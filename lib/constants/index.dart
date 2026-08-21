class AppConstants {
  static const String defaultNoteId = 'default-room';
  static const String defaultTagColor = '#3b82f6';
  static const String welcomeTag = 'welcome';
  static const String vaultRootFolderName = 'krag-vault';
  static const String workspaceSettingsFileName = 'workspace_settings.json';
}

class StorageKeys {
  static const String vaultSalt = 'vault_salt';
  static const String vaultKek = 'vault_kek';
  static const String rootFolderId = 'vault_root_folder_id';
  static const String configFolderId = 'vault_config_folder_id';
  static const String docsFolderId = 'vault_docs_folder_id';
  static const String wrappedKeysTimestamp = 'vault_wrapped_keys_timestamp';
  static const String hasSeenLandingPage = 'has_seen_landing_page';
  static const String tags = 'tags';
  static const String noteFilters = 'note_filters';
  static const String currentNoteId = 'current_note_id';
  static const String searchIndex = 'search_index_encrypted';
  static const String googleTokens = 'google_drive_tokens';
  static const String pkceVerifier = 'pkce_code_verifier';
  static const String openTabs = 'open_tabs';
}

class FolderPaths {
  static const String root = AppConstants.vaultRootFolderName;
  static const String config = '${AppConstants.vaultRootFolderName}/config';
  static const String docs = '${AppConstants.vaultRootFolderName}/docs';
}

class ViewTypes {
  static const String editor = 'editor';
  static const String graph = 'graph';
  static const String list = 'list';
}

class FileTypes {
  static const String salt = FolderPaths.config;
  static const String wrappedKeys = FolderPaths.config;
  static const String index = FolderPaths.config;
  static const String note = FolderPaths.docs;
  static const String workspaceSettings = FolderPaths.config;
}
