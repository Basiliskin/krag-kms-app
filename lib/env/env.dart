import 'package:envied/envied.dart';

part 'env.g.dart';

//flutter pub run build_runner build --delete-conflicting-outputs

@Envied(path: '.env')
abstract class Env {
  @EnviedField(varName: 'GOOGLE_CLIENT_SECRET', obfuscate: true)
  static final String googleClientSecret = _Env.googleClientSecret;

  @EnviedField(varName: 'GOOGLE_CLIENT_ID', obfuscate: true)
  static final String googleClientId = _Env.googleClientId;
}
