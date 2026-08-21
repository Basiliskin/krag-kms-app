import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:universal_html/html.dart' as html;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:firebase_auth/firebase_auth.dart';
import '../env/env.dart';
import '../utils/logger.dart';

class GoogleAuthService {
  static final GoogleAuthService _instance = GoogleAuthService._internal();

  factory GoogleAuthService() => _instance;

  GoogleAuthService._internal() {
    KragLogger.info(
      LogDomain.auth,
      'GoogleAuthService initialized. Web Client ID: ${_clientId.substring(0, min(_clientId.length, 20))}...',
    );
  }

  // UPDATED CONFIGURATION:
  // 1. For Android: We set 'serverClientId' to NULL. This forces the plugin to use the
  //    'default_web_client_id' from the generated 'google-services.json' resources.
  //    This triggers the ID Token flow (required for Firebase) instead of the Server Auth Code flow.
  // 2. For Web: We explicitly set 'clientId' to the Web Client ID.
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'openid',
      'profile',
      drive.DriveApi.driveScope,
    ],
    signInOption: SignInOption.standard,
    // CRITICAL FIX: Do NOT set serverClientId on Android if you want an idToken for Firebase.
    // Setting it triggers the "Server Auth Code" flow, which often returns a null idToken.
    serverClientId: null,
    clientId: kIsWeb ? Env.googleClientId : null,
  );

  static const String _authUrl = 'https://accounts.google.com/o/oauth2/v2/auth';
  static const String _tokenUrl = 'https://oauth2.googleapis.com/token';
  static const String _scope =
      'https://www.googleapis.com/auth/drive.file email openid profile';
  static const String _storageKey = 'google_drive_tokens';
  static const String _verifierKey = 'pkce_code_verifier';

  static final String _clientId = Env.googleClientId;
  static final String _clientSecret = Env.googleClientSecret;

  final _authStateController = StreamController<bool>.broadcast();
  Stream<bool> get onAuthStateChanged => _authStateController.stream;

  Map<String, dynamic>? _tokens;
  bool _isInitialized = false;

  Future<bool> restoreSession() async {
    KragLogger.info(LogDomain.auth, 'Restoring session...');
    if (kIsWeb) {
      if (_isInitialized) {
        final isAuth = isAuthenticated();
        KragLogger.info(
          LogDomain.auth,
          'Session already initialized. Authenticated: $isAuth',
        );
        return isAuth;
      }

      final uri = Uri.parse(html.window.location.href);
      if (uri.queryParameters.containsKey('code')) {
        KragLogger.info(LogDomain.auth, 'Auth code detected in URL');
        try {
          await _handleWebCallback(uri.queryParameters['code']!);
          return true;
        } catch (e, stack) {
          KragLogger.error(
            LogDomain.auth,
            'Failed to handle web callback',
            e,
            stack,
          );
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);

      if (jsonString != null) {
        try {
          _tokens = jsonDecode(jsonString);
          _isInitialized = true;
          KragLogger.info(
            LogDomain.auth,
            'Session restored from local storage',
          );
          _authStateController.add(true);
          return true;
        } catch (e, stack) {
          KragLogger.error(
            LogDomain.auth,
            'Failed to parse stored tokens',
            e,
            stack,
          );
          await signOut();
        }
      } else {
        KragLogger.info(LogDomain.auth, 'No stored session found');
      }
      _isInitialized = true;
      return false;
    } else {
      try {
        if (_googleSignIn.currentUser != null) {
          KragLogger.info(
            LogDomain.auth,
            'Native: Current user already exists',
          );
          return true;
        }
        final account = await _googleSignIn.signInSilently();
        final success = account != null;
        KragLogger.info(
          LogDomain.auth,
          'Native: Silent sign-in result: $success',
        );
        if (success) {
          _authStateController.add(true);
        }
        return success;
      } catch (e, stack) {
        KragLogger.error(
          LogDomain.auth,
          'Native: Silent sign-in failed',
          e,
          stack,
        );
        return false;
      }
    }
  }

  bool isAuthenticated() {
    if (kIsWeb) {
      return _tokens != null && _tokens!.containsKey('access_token');
    } else {
      return _googleSignIn.currentUser != null;
    }
  }

  Future<void> signIn() async {
    KragLogger.info(LogDomain.auth, 'Initiating sign-in...');
    if (kIsWeb) {
      await _signInWeb();
    } else {
      await _signInNative();
    }
  }

  Future<void> _signInNative() async {
    try {
      KragLogger.info(
        LogDomain.auth,
        'Native: Requesting scopes: ${_googleSignIn.scopes.join(", ")}',
      );
      // Note: serverClientId is null here to force ID Token flow via google-services.json
      KragLogger.info(
        LogDomain.auth,
        'Native: Using default google-services.json configuration for ID Token flow',
      );

      final GoogleSignInAccount? currentUser = await _googleSignIn.signIn();

      if (currentUser == null) {
        KragLogger.error(LogDomain.auth,
            'Native: No current user after sign-in (User cancelled)');
        throw Exception('Google Sign-In cancelled by user');
      }

      KragLogger.info(
        LogDomain.auth,
        'Native: Sign-in successful. User: ${currentUser.email}',
      );
      KragLogger.info(
        LogDomain.auth,
        'Native: Retrieving authentication tokens for Firebase',
      );

      final GoogleSignInAuthentication googleAuth =
          await currentUser.authentication;
      final String? accessToken = googleAuth.accessToken;
      final String? idToken = googleAuth.idToken;

      KragLogger.info(
        LogDomain.auth,
        'Native: Token acquisition result - accessToken present: ${accessToken != null}, idToken present: ${idToken != null}',
      );

      if (accessToken != null && idToken != null) {
        await _authenticateWithFirebase(accessToken, idToken);
      } else {
        _handleMissingTokens(accessToken, idToken);
      }

      _authStateController.add(true);
      KragLogger.info(LogDomain.auth, 'Native: Sign-in completed successfully');
    } on PlatformException catch (e) {
      _handlePlatformException(e);
    } catch (e, stack) {
      KragLogger.error(LogDomain.auth, 'Native: Sign-in failed', e, stack);
      rethrow;
    }
  }

  Future<void> _authenticateWithFirebase(
      String accessToken, String idToken) async {
    KragLogger.info(
      LogDomain.auth,
      'Native: Both tokens acquired successfully. Creating Firebase credential...',
    );
    final credential = GoogleAuthProvider.credential(
      accessToken: accessToken,
      idToken: idToken,
    );

    try {
      final userCredential =
          await FirebaseAuth.instance.signInWithCredential(credential);
      final firebaseUser = userCredential.user;

      if (firebaseUser != null) {
        KragLogger.info(
          LogDomain.auth,
          'Native: Firebase sign-in successful. User ID: ${firebaseUser.uid}, Email: ${firebaseUser.email}',
        );
        KragLogger.info(
            LogDomain.auth, 'Native: Waiting for auth state propagation...');
        await Future.delayed(const Duration(milliseconds: 100));
        KragLogger.info(
            LogDomain.auth, 'Native: Auth state propagation complete');
      } else {
        KragLogger.error(
            LogDomain.auth, 'Native: Firebase sign-in returned null user');
        throw Exception('Firebase authentication failed: No user returned');
      }
    } catch (e, stack) {
      KragLogger.error(
          LogDomain.auth, 'Native: Firebase sign-in failed', e, stack);
      throw Exception('Firebase authentication failed: $e');
    }
  }

  void _handleMissingTokens(String? accessToken, String? idToken) {
    KragLogger.error(
      LogDomain.auth,
      'Native: Missing authentication tokens!\n'
      ' accessToken present: ${accessToken != null}\n'
      ' idToken present: ${idToken != null}\n'
      ' scopes requested: ${_googleSignIn.scopes.join(", ")}',
    );

    throw Exception(
      'Failed to retrieve authentication tokens from Google Sign-In.\n'
      'Missing: ${accessToken == null ? "accessToken " : ""}${idToken == null ? "idToken" : ""}\n\n'
      'Troubleshooting steps:\n'
      '1. Ensure "google-services.json" is present and up-to-date in android/app/\n'
      '2. Verify SHA-1 fingerprint in Firebase Console matches your debug.keystore\n'
      '3. Check that Google Sign-In is enabled in Firebase Authentication\n'
      '4. Verify scopes include: email, openid, profile\n'
      '5. Try clearing app data and signing in again',
    );
  }

  void _handlePlatformException(PlatformException e) {
    KragLogger.error(LogDomain.auth, 'Native: Sign-in platform error', e);
    final message = e.message ?? '';
    final details = e.details?.toString() ?? '';

    if (message.contains('ApiException: 10') ||
        details.contains('ApiException: 10') ||
        (e.code == 'sign_in_failed' && message.contains('10'))) {
      throw Exception(
        'Configuration Error (ApiException 10): The Android app signing certificate (SHA-1) '
        'matches neither the debug nor release keystore registered in the Firebase/Google Cloud Console. '
        'Please see ANDROID_SETUP.md for resolution steps.',
      );
    }

    if (message.contains('ApiException: 12500') ||
        details.contains('ApiException: 12500') ||
        message.contains('12500')) {
      throw Exception(
        'Configuration Error (ApiException 12500): Sign-in is currently unavailable. '
        'This typically indicates:\n'
        '1. Missing or incorrect OAuth 2.0 Client ID in Firebase Console\n'
        '2. SHA-1 certificate fingerprint not registered\n'
        '3. Google Sign-In not enabled in Firebase Authentication\n'
        'Please verify your Firebase and Google Cloud Console configuration. '
        'See ANDROID_SETUP.md for detailed instructions.',
      );
    }

    if (e.code == 'network_error' ||
        message.contains('network') ||
        message.contains('NETWORK_ERROR')) {
      throw Exception(
        'Network Error: Unable to connect to Google Sign-In services. '
        'Please check your internet connection and try again.',
      );
    }

    if (e.code == 'sign_in_failed') {
      throw Exception(
        'Google Sign-In Failed: ${e.message ?? "Unknown error"}. '
        'This may indicate a configuration issue. '
        'Error code: ${e.code}, Details: ${e.details}',
      );
    }

    throw e;
  }

  Future<void> signOut() async {
    KragLogger.info(LogDomain.auth, 'Signing out...');
    try {
      await FirebaseAuth.instance.signOut();
      KragLogger.info(LogDomain.auth, 'Firebase sign-out successful');
    } catch (e, stack) {
      KragLogger.error(LogDomain.auth, 'Firebase sign-out failed', e, stack);
    }

    if (kIsWeb) {
      _tokens = null;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
      _authStateController.add(false);
      KragLogger.info(LogDomain.auth, 'Web: Sign-out completed');
    } else {
      await _googleSignIn.disconnect();
      _authStateController.add(false);
      KragLogger.info(LogDomain.auth, 'Native: Sign-out completed');
    }
  }

  Future<http.Client?> getAuthenticatedClient() async {
    if (kIsWeb) {
      if (!isAuthenticated()) return null;
      return _AutoRefreshingClient(this);
    } else {
      final client = await _googleSignIn.authenticatedClient();
      if (client != null) {
        _authStateController.add(true);
      }
      return client;
    }
  }

  Future<void> _signInWeb() async {
    KragLogger.info(LogDomain.auth, 'Web: Generating PKCE challenge');
    final random = Random.secure();
    final values = List<int>.generate(32, (i) => random.nextInt(256));
    final verifier = base64Url.encode(values).replaceAll('=', '');

    html.window.localStorage[_verifierKey] = verifier;

    final algorithm = Sha256();
    final hash = await algorithm.hash(utf8.encode(verifier));
    final challenge = base64Url.encode(hash.bytes).replaceAll('=', '');

    final redirectUri = _getWebRedirectUri();
    KragLogger.info(
      LogDomain.auth,
      'Web: Redirect URI calculated as: $redirectUri',
    );

    final params = {
      'client_id': _clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': _scope,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
      'access_type': 'offline',
      'prompt': 'consent',
    };

    final uri = Uri.parse(_authUrl).replace(queryParameters: params);
    KragLogger.info(LogDomain.auth, 'Web: Redirecting to Auth URL');
    html.window.location.href = uri.toString();
  }

  Future<void> _handleWebCallback(String code) async {
    KragLogger.info(LogDomain.auth, 'Web: Handling callback code');
    final verifier = html.window.localStorage[_verifierKey];
    if (verifier == null) {
      KragLogger.error(
        LogDomain.auth,
        'PKCE verifier not found in local storage',
      );
      throw Exception('PKCE verifier not found');
    }
    html.window.localStorage.remove(_verifierKey);

    final redirectUri = _getWebRedirectUri();
    final body = {
      'client_id': _clientId,
      'code': code,
      'code_verifier': verifier,
      'grant_type': 'authorization_code',
      'redirect_uri': redirectUri,
    };

    if (_clientSecret.isNotEmpty) {
      body['client_secret'] = _clientSecret;
    }

    KragLogger.info(LogDomain.auth, 'Web: Exchanging code for token...');
    final response = await http.post(
      Uri.parse(_tokenUrl),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: body,
    );

    if (response.statusCode != 200) {
      KragLogger.error(
        LogDomain.auth,
        'Token exchange failed. Status: ${response.statusCode}, Body: ${response.body}',
      );
      throw Exception('Token exchange failed: ${response.body}');
    }

    KragLogger.info(LogDomain.auth, 'Web: Token exchange successful');
    final newTokens = jsonDecode(response.body) as Map<String, dynamic>;
    KragLogger.info(
      LogDomain.auth,
      'Web: Received tokens - has id_token: ${newTokens.containsKey('id_token')}, '
      'has access_token: ${newTokens.containsKey('access_token')}',
    );

    await _saveWebTokens(newTokens);

    final idToken = newTokens['id_token'] as String?;
    final accessToken = newTokens['access_token'] as String?;

    if (idToken != null && accessToken != null) {
      KragLogger.info(
        LogDomain.auth,
        'Web: Creating Firebase credential with id_token and access_token',
      );
      try {
        final credential = GoogleAuthProvider.credential(
          idToken: idToken,
          accessToken: accessToken,
        );
        final userCredential =
            await FirebaseAuth.instance.signInWithCredential(credential);
        final firebaseUser = userCredential.user;

        if (firebaseUser != null) {
          KragLogger.info(
            LogDomain.auth,
            'Web: Firebase sign-in successful. User ID: ${firebaseUser.uid}, Email: ${firebaseUser.email}',
          );
          KragLogger.info(
              LogDomain.auth, 'Web: Waiting for auth state propagation...');
          await Future.delayed(const Duration(milliseconds: 200));
          final currentUser = FirebaseAuth.instance.currentUser;
          if (currentUser?.uid == firebaseUser.uid) {
            KragLogger.info(
                LogDomain.auth, 'Web: Auth state verified and propagated');
          } else {
            KragLogger.warn(LogDomain.auth,
                'Web: Auth state may not have fully propagated');
          }
        } else {
          KragLogger.error(
              LogDomain.auth, 'Web: Firebase sign-in returned null user');
          throw Exception('Firebase authentication failed: No user returned');
        }
      } catch (e, stack) {
        KragLogger.error(
            LogDomain.auth, 'Web: Firebase sign-in failed', e, stack);
        throw Exception('Firebase authentication failed: $e');
      }
    } else {
      KragLogger.error(
        LogDomain.auth,
        'Web: Missing authentication tokens for Firebase (idToken: ${idToken != null}, accessToken: ${accessToken != null}). '
        'This likely means the openid scope was not properly requested.',
      );
      throw Exception(
        'Failed to retrieve id_token from Google OAuth. Ensure openid scope is requested.',
      );
    }

    _authStateController.add(true);
    html.window.history.replaceState({}, '', redirectUri);
  }

  Future<String> getWebAccessToken() async {
    if (_tokens == null) throw Exception('Not authenticated');
    return _tokens!['access_token'];
  }

  Future<void> refreshWebAccessToken() async {
    KragLogger.info(LogDomain.auth, 'Web: Refreshing access token...');
    final refreshToken = _tokens?['refresh_token'];
    if (refreshToken == null) {
      KragLogger.error(LogDomain.auth, 'No refresh token available');
      throw Exception('No refresh token available');
    }

    final body = {
      'client_id': _clientId,
      'refresh_token': refreshToken,
      'grant_type': 'refresh_token',
    };

    if (_clientSecret.isNotEmpty) {
      body['client_secret'] = _clientSecret;
    }

    final response = await http.post(
      Uri.parse(_tokenUrl),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: body,
    );

    if (response.statusCode != 200) {
      KragLogger.error(
        LogDomain.auth,
        'Token refresh failed. Status: ${response.statusCode}, Body: ${response.body}',
      );
      await signOut();
      throw Exception('Failed to refresh token');
    }

    KragLogger.info(LogDomain.auth, 'Web: Token refresh successful');
    final newTokens = jsonDecode(response.body) as Map<String, dynamic>;
    await _saveWebTokens(newTokens);
  }

  Future<void> _saveWebTokens(Map<String, dynamic> newTokens) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = _tokens ?? {};
    final merged = {...existing, ...newTokens};

    if (!merged.containsKey('refresh_token') &&
        existing.containsKey('refresh_token')) {
      merged['refresh_token'] = existing['refresh_token'];
    }

    _tokens = merged;
    await prefs.setString(_storageKey, jsonEncode(merged));
  }

  String _getWebRedirectUri() {
    final uri = Uri.parse(html.window.location.href);
    String base = uri.origin + uri.path;
    if (base.contains('callback')) {
      return base;
    }
    return "$base${base.endsWith('/') ? '' : '/'}callback";
  }
}

class _AutoRefreshingClient extends http.BaseClient {
  final GoogleAuthService _authService;
  final http.Client _inner = http.Client();

  _AutoRefreshingClient(this._authService);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      final token = await _authService.getWebAccessToken();
      request.headers['Authorization'] = 'Bearer $token';
    } catch (_) {}

    final response = await _inner.send(request);

    if (response.statusCode == 401) {
      KragLogger.warn(
        LogDomain.network,
        '401 Unauthorized detected for ${request.url}',
      );
      await response.stream.drain();

      try {
        await _authService.refreshWebAccessToken();
        final newToken = await _authService.getWebAccessToken();
        final newRequest = _copyRequest(request);
        newRequest.headers['Authorization'] = 'Bearer $newToken';
        KragLogger.info(LogDomain.network, 'Retrying request with new token');
        return await _inner.send(newRequest);
      } catch (e, stack) {
        KragLogger.error(
          LogDomain.auth,
          'Session expired or refresh failed during retry',
          e,
          stack,
        );
        _authService._authStateController.add(false);
        throw Exception('Session expired');
      }
    }

    return response;
  }

  http.BaseRequest _copyRequest(http.BaseRequest request) {
    http.BaseRequest requestCopy;

    if (request is http.Request) {
      requestCopy = http.Request(request.method, request.url)
        ..encoding = request.encoding
        ..bodyBytes = request.bodyBytes;
    } else if (request is http.MultipartRequest) {
      requestCopy = http.MultipartRequest(request.method, request.url)
        ..fields.addAll(request.fields)
        ..files.addAll(request.files);
    } else {
      throw Exception('Unsupported request type for retry');
    }

    requestCopy.headers.addAll(request.headers);
    return requestCopy;
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
