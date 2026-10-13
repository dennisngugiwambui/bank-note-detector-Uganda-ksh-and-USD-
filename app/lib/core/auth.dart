import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UserProfile {
  final String name;
  final String email;
  final bool guest;
  const UserProfile({required this.name, required this.email, this.guest = false});

  String get firstName => name.trim().split(' ').first;
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  @override
  String toString() => message;
}

/// Authentication contract. The app depends only on this interface.
///
/// [LocalAuthService] keeps accounts on the device, so the app works fully
/// offline. A resale build that needs cloud accounts, sync or licensing can
/// implement this with Firebase Auth, Supabase or its own backend, then swap
/// it in main.dart. No UI changes are needed.
abstract class AuthService extends ChangeNotifier {
  UserProfile? get currentUser;
  bool get isSignedIn => currentUser != null;
  Future<void> signUp({required String name, required String email, required String password});
  Future<void> signIn({required String email, required String password});
  Future<void> continueAsGuest();
  Future<void> signOut();
}

class LocalAuthService extends AuthService {
  final SharedPreferences _prefs;
  UserProfile? _user;
  LocalAuthService._(this._prefs);

  static Future<LocalAuthService> load() async {
    final s = LocalAuthService._(await SharedPreferences.getInstance());
    final session = s._prefs.getString('session');
    if (session == 'guest') {
      s._user = const UserProfile(name: 'Guest', email: '', guest: true);
    } else if (session != null) {
      final acc = s._accounts()[session];
      if (acc != null) s._user = UserProfile(name: acc['name'] as String, email: session);
    }
    return s;
  }

  @override
  UserProfile? get currentUser => _user;

  Map<String, dynamic> _accounts() =>
      jsonDecode(_prefs.getString('accounts') ?? '{}') as Map<String, dynamic>;

  static String _hash(String password, String salt) {
    // Iterated SHA-256 with a per-user salt. Good enough for an on-device
    // lock. A cloud backend should use its own password hashing.
    List<int> digest = utf8.encode('$salt:$password');
    for (var i = 0; i < 10000; i++) {
      digest = sha256.convert(digest).bytes;
    }
    return base64Encode(digest);
  }

  @override
  Future<void> signUp({required String name, required String email, required String password}) async {
    final key = email.trim().toLowerCase();
    final accounts = _accounts();
    if (accounts.containsKey(key)) throw AuthException('An account with this email already exists.');
    final rnd = Random.secure();
    final salt = base64Encode(List<int>.generate(16, (_) => rnd.nextInt(256)));
    accounts[key] = {'name': name.trim(), 'salt': salt, 'hash': _hash(password, salt)};
    await _prefs.setString('accounts', jsonEncode(accounts));
    await _startSession(key, name.trim());
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    final key = email.trim().toLowerCase();
    final acc = _accounts()[key] as Map<String, dynamic>?;
    if (acc == null || _hash(password, acc['salt'] as String) != acc['hash']) {
      throw AuthException('Email or password is incorrect.');
    }
    await _startSession(key, acc['name'] as String);
  }

  @override
  Future<void> continueAsGuest() async {
    await _prefs.setString('session', 'guest');
    _user = const UserProfile(name: 'Guest', email: '', guest: true);
    notifyListeners();
  }

  Future<void> _startSession(String email, String name) async {
    await _prefs.setString('session', email);
    _user = UserProfile(name: name, email: email);
    notifyListeners();
  }

  @override
  Future<void> signOut() async {
    await _prefs.remove('session');
    _user = null;
    notifyListeners();
  }
}
