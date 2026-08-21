import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;

final GoogleSignIn? googleSignInWebSingleton = kIsWeb
    ? GoogleSignIn(
        scopes: [
          'email',
          'openid',
          'profile',
          drive.DriveApi.driveFileScope,
        ],
        signInOption: SignInOption.standard,
      )
    : null;
