
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:shonenx/core/network/auth/authenticator.dart';
import 'package:shonenx/core/network/http_client.dart';
import 'package:shonenx/core/utils/env.dart';
import 'package:shonenx/features/tracking/domain/models/tracker_type.dart';

import 'package:shonenx/features/tracking/domain/models/tracker_credentials.dart';

class AnilistAuthenticator implements Authenticator {
  final TrackerCredentials? customCredentials;

  AnilistAuthenticator({this.customCredentials});

  static final HTTP _http = HTTP();

  String get _clientId =>
      customCredentials?.clientId ??
      Env.ANILIST_CLIENT_ID_LIST.first;

  String get _clientSecret =>
      customCredentials?.clientSecret ??
      Env.ANILIST_CLIENT_SECRET_LIST.first;

  @override
  String get redirectUri => 'shonenx://callback';

  @override
  String get callbackScheme => 'shonenx';

  @override
  String get providerName => TrackerType.anilist.name;

  @override
  List<String> get apiHosts => ['graphql.anilist.co'];

  @override
  Future<String> performLogin() async {
    final url = Uri.https('anilist.co', '/api/v2/oauth/authorize', {
      'client_id': _clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
    });

    final result = await FlutterWebAuth2.authenticate(
      url: url.toString(),
      callbackUrlScheme: callbackScheme,
      options: const FlutterWebAuth2Options(useWebview: true),
    );

    final code = Uri.parse(result).queryParameters['code'];

    if (code == null || code.isEmpty) {
      throw Exception('AniList Auth Error: Failed to get authorization code.');
    }

    final tokenResponse = await _http.post(
      'https://anilist.co/api/v2/oauth/token',
      body: {
        "grant_type": "authorization_code",
        "client_id": _clientId,
        "client_secret": _clientSecret,
        "redirect_uri": redirectUri,
        "code": code,
      },
      headers: {
        "Content-Type": "application/json",
        "Accept": "application/json",
      },
    );

    final String? accessToken = tokenResponse.json['access_token'];

    if (accessToken == null || accessToken.isEmpty) {
      throw Exception('AniList Auth Error: Failed to exchange token.');
    }

    return accessToken;
  }
}
