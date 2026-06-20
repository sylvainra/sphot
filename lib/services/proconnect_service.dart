import 'package:flutter_appauth/flutter_appauth.dart';

class ProConnectService {
  static final FlutterAppAuth appAuth = FlutterAppAuth();

  static const String clientId =
      'b049727707e6a6e982f443d5e8ea1eb3217fea78643f522ab441806875f488cd';

  static const String redirectUrl = 'https://sphot.app/auth/callback';

  static const String discoveryUrl =
    'https://fca.integ01.dev-agentconnect.fr/api/v2/.well-known/openid-configuration';

  Future<AuthorizationTokenResponse?> login() async {
    return await appAuth.authorizeAndExchangeCode(
      AuthorizationTokenRequest(
        clientId,
        redirectUrl,
        discoveryUrl: discoveryUrl,
        scopes: const [
          'openid',
          'email',
          'profile',
        ],
      ),
    );
  }
}