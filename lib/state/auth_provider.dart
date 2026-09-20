import 'package:flutter/foundation.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../core/api_client.dart';
import '../core/models.dart';

class AuthProvider extends ChangeNotifier {
  final ApiClient api;
  AuthProvider(this.api);

  AppUser? user;
  bool loading = true;
  bool get isLoggedIn => user != null;

  Future<void> bootstrap() async {
    final token = await api.accessToken;
    if (token == null) {
      loading = false;
      notifyListeners();
      return;
    }
    await refreshProfile();
    loading = false;
    notifyListeners();
  }

  Future<void> refreshProfile() async {
    try {
      user = await api.getMyProfile();
    } catch (_) {
      user = null;
    }
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final result = await api.login(email, password);
    await api.setTokens(result['accessToken'], result['refreshToken']);
    user = AppUser.fromJson(result['user']);
    notifyListeners();
  }

  Future<void> register(String email, String password, String fullName) async {
    await api.register(email, password, fullName);
  }

  Future<void> verifyEmail(String email, String code) async {
    final result = await api.verifyEmail(email, code);
    if (result['accessToken'] != null) {
      await api.setTokens(result['accessToken'], result['refreshToken']);
      user = AppUser.fromJson(result['user']);
      notifyListeners();
    }
  }

  /// Returns false if the user cancelled the Google chooser (not an error).
  Future<bool> loginWithGoogle() async {
    final googleSignIn = GoogleSignIn(
      scopes: ['email'],
      // Same Web OAuth client the backend verifies the idToken against
      // (auth.service.ts uses GOOGLE_CLIENT_ID as the audience). Without
      // this, Android never requests an idToken and it comes back null.
      serverClientId:
          '339024181722-msts0gkl8v1iavf5i8tp03iucl39rhmv.apps.googleusercontent.com',
    );
    final account = await googleSignIn.signIn();
    if (account == null) return false;
    final googleAuth = await account.authentication;
    final idToken = googleAuth.idToken;
    if (idToken == null) {
      throw Exception('Google no devolvió un token válido');
    }
    final result = await api.socialLogin(
      provider: 'google',
      token: idToken,
      email: account.email,
      name: account.displayName,
      photoUrl: account.photoUrl,
    );
    await api.setTokens(result['accessToken'], result['refreshToken']);
    user = AppUser.fromJson(result['user']);
    notifyListeners();
    return true;
  }

  /// Returns false if the user cancelled the Facebook dialog (not an error).
  Future<bool> loginWithFacebook() async {
    final result = await FacebookAuth.instance.login(permissions: ['email', 'public_profile']);
    if (result.status == LoginStatus.cancelled) return false;
    if (result.status != LoginStatus.success || result.accessToken == null) {
      throw Exception(result.message ?? 'Facebook no devolvió un token válido');
    }
    final data = await FacebookAuth.instance.getUserData(fields: 'email,name,picture.type(large)');
    final email = data['email'] as String?;
    if (email == null) {
      throw Exception('Tu cuenta de Facebook no tiene un correo asociado');
    }
    final apiResult = await api.socialLogin(
      provider: 'facebook',
      token: result.accessToken!.tokenString,
      email: email,
      name: data['name'] as String?,
      photoUrl: (data['picture']?['data']?['url']) as String?,
    );
    await api.setTokens(apiResult['accessToken'], apiResult['refreshToken']);
    user = AppUser.fromJson(apiResult['user']);
    notifyListeners();
    return true;
  }

  Future<void> logout() async {
    await api.logout();
    await api.clearTokens();
    user = null;
    notifyListeners();
  }
}
