import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class _TokenWriteEntry {
  Future<void>? write;
  int pendingRegistrations = 0;
}

class FcmService {
  FcmService._();

  static final FcmService instance = FcmService._();
  static const _cleanupTimeout = Duration(seconds: 2);
  static const _registrationTimeout = Duration(seconds: 10);
  static const _maxTrackedTokenHashes = 32;

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  Future<void> _registrationQueue = Future<void>.value();
  final Map<String, Map<String, _TokenWriteEntry>> _tokenWriteTracking = {};
  final Map<String, int> _loggingOutUidCounts = {};
  String? _registeredUid;
  String? _registeredTokenHash;
  int _sessionEpoch = 0;
  bool _hasReceivedInitialAuthState = false;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized || !_isAndroid) return;
    _initialized = true;

    StreamSubscription<String>? tokenRefreshSubscription;
    StreamSubscription<User?>? authSubscription;
    try {
      tokenRefreshSubscription = _messaging.onTokenRefresh.listen(
        (token) {
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) _queueRegistration(user, token);
        },
        onError: (Object error, StackTrace stackTrace) {
          _logError('FCM token refresh failed', error);
        },
      );
      authSubscription = FirebaseAuth.instance.authStateChanges().listen(
        (user) {
          if (_hasReceivedInitialAuthState) {
            _sessionEpoch++;
          } else {
            _hasReceivedInitialAuthState = true;
          }
          if (_registeredUid != user?.uid) {
            _registeredUid = null;
            _registeredTokenHash = null;
          }
          if (user != null && !_isLoggingOut(user.uid)) {
            _queueRegistration(user);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          _logError('Firebase authentication state listener failed', error);
        },
      );
    } catch (error) {
      _initialized = false;
      await tokenRefreshSubscription?.cancel();
      await authSubscription?.cancel();
      _logError('FCM initialization failed', error);
    }
  }

  Future<bool> requestNotificationPermission() async {
    if (!_isAndroid) return false;
    try {
      final settings = await _messaging.requestPermission();
      final granted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;
      final user = FirebaseAuth.instance.currentUser;
      if (granted && user != null) _queueRegistration(user);
      return granted;
    } on FirebaseException catch (error) {
      _logError('FCM permission request failed', error);
      return false;
    } on PlatformException catch (error) {
      _logError('FCM permission request failed', error);
      return false;
    } catch (error) {
      _logError('FCM permission request failed', error);
      return false;
    }
  }

  Future<void> signOut() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      await FirebaseAuth.instance.signOut();
      return;
    }

    final uid = user.uid;
    final tokenHash = _registeredUid == uid ? _registeredTokenHash : null;
    _loggingOutUidCounts[uid] = (_loggingOutUidCounts[uid] ?? 0) + 1;
    final cleanupEpoch = ++_sessionEpoch;
    _registeredUid = null;
    _registeredTokenHash = null;

    try {
      await _cleanupLogoutTokens(uid, tokenHash, cleanupEpoch);
    } catch (error) {
      _logError('FCM logout cleanup failed; sign-out will continue', error);
    } finally {
      final stillSigningOutUser =
          FirebaseAuth.instance.currentUser?.uid == uid &&
          (!_isAndroid || _sessionEpoch == cleanupEpoch);
      try {
        if (stillSigningOutUser) await FirebaseAuth.instance.signOut();
      } finally {
        _finishLogout(uid);
      }
    }
  }

  Future<void> unregisterCurrentDevice() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !_isAndroid) return;
    final tokenHash = _registeredUid == user.uid ? _registeredTokenHash : null;
    if (tokenHash == null) return;

    try {
      await _deleteToken(user.uid, tokenHash).timeout(_cleanupTimeout);
      if (_registeredUid == user.uid && _registeredTokenHash == tokenHash) {
        _registeredUid = null;
        _registeredTokenHash = null;
      }
    } on TimeoutException {
      _logDebug('FCM cleanup timed out; continuing account cleanup.');
    } catch (error) {
      _logError('FCM cleanup failed; continuing account cleanup', error);
    }
  }

  void _queueRegistration(User user, [String? refreshedToken]) {
    final sessionEpoch = _sessionEpoch;
    _registrationQueue = _registrationQueue
        .then((_) async {
          await _registerToken(
            user,
            refreshedToken,
            sessionEpoch,
          ).timeout(_registrationTimeout);
        })
        .catchError((Object error, StackTrace stackTrace) {
          _logError('FCM token registration failed', error);
        });
  }

  Future<void> _registerToken(
    User user,
    String? knownToken,
    int sessionEpoch,
  ) async {
    if (!_isCurrentRegistration(user.uid, sessionEpoch)) return;

    String? pendingTokenHash;
    try {
      final token =
          knownToken ??
          await _messaging.getToken().timeout(_registrationTimeout);
      if (token == null || token.isEmpty) {
        _logDebug('FCM did not provide a device token.');
        return;
      }
      if (!_isCurrentRegistration(user.uid, sessionEpoch)) return;

      final tokenHash = _hashToken(token);
      final previousHash =
          _registeredUid == user.uid ? _registeredTokenHash : null;

      if (previousHash != tokenHash) {
        if (!_rememberPendingTokenHash(user.uid, tokenHash)) {
          _logDebug(
            'FCM registration deferred; too many token writes are still pending.',
          );
          return;
        }
        pendingTokenHash = tokenHash;
        await _writeToken(user.uid, tokenHash, token, sessionEpoch);
      }
      if (!_isCurrentRegistration(user.uid, sessionEpoch)) return;

      _registeredUid = user.uid;
      _registeredTokenHash = tokenHash;
      if (pendingTokenHash != null) {
        _forgetPendingTokenHash(user.uid, pendingTokenHash);
        pendingTokenHash = null;
      }

      if (previousHash != null && previousHash != tokenHash) {
        try {
          await _deleteToken(user.uid, previousHash).timeout(_cleanupTimeout);
        } on TimeoutException {
          _logDebug('Previous FCM token cleanup timed out.');
        } catch (error) {
          _logError('Previous FCM token cleanup failed', error);
        }
      }
    } on FirebaseException catch (error) {
      _logError('FCM token could not be stored', error);
    } on PlatformException catch (error) {
      _logError('FCM token could not be obtained', error);
    } catch (error) {
      _logError('FCM token registration failed', error);
    } finally {
      if (pendingTokenHash != null) {
        _forgetPendingTokenHash(user.uid, pendingTokenHash);
      }
    }
  }

  Future<void> _writeToken(
    String uid,
    String tokenHash,
    String token,
    int sessionEpoch,
  ) async {
    if (!_isCurrentRegistration(uid, sessionEpoch)) return;

    final tokenRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('fcmTokens')
        .doc(tokenHash);
    try {
      await _trackTokenWrite(
        uid,
        tokenHash,
        () => tokenRef.update({
          'token': token,
          'platform': 'android',
          'updatedAt': FieldValue.serverTimestamp(),
        }),
      );
    } on FirebaseException catch (error) {
      if (error.code != 'not-found') rethrow;
      if (!_isCurrentRegistration(uid, sessionEpoch)) return;
      await _trackTokenWrite(
        uid,
        tokenHash,
        () => tokenRef.set({
          'token': token,
          'platform': 'android',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }),
      );
    }
  }

  Future<void> _trackTokenWrite(
    String uid,
    String tokenHash,
    Future<void> Function() startWrite,
  ) async {
    final entry = _tokenWriteTracking[uid]?[tokenHash];
    if (entry == null) {
      throw StateError('FCM token write was not reserved for tracking.');
    }

    final existingWrite = entry.write;
    if (existingWrite != null) {
      // The same UID/hash represents the same token document. Reuse its
      // pending write instead of creating another untracked duplicate.
      await existingWrite.timeout(_registrationTimeout);
      return;
    }

    final write = startWrite();
    entry.write = write;

    // Keep timed-out writes tracked until the underlying Firestore operation
    // actually settles. Future.timeout does not cancel that operation.
    unawaited(
      write.then<void>(
        (_) => _finishTokenWrite(uid, tokenHash, entry, write),
        onError: (Object error, StackTrace stackTrace) {
          _finishTokenWrite(uid, tokenHash, entry, write);
        },
      ),
    );

    await write.timeout(_registrationTimeout);
  }

  void _finishTokenWrite(
    String uid,
    String tokenHash,
    _TokenWriteEntry entry,
    Future<void> write,
  ) {
    if (!identical(_tokenWriteTracking[uid]?[tokenHash], entry) ||
        !identical(entry.write, write)) {
      return;
    }
    entry.write = null;
    _removeTokenEntryIfFinished(uid, tokenHash, entry);
  }

  bool _rememberPendingTokenHash(String uid, String tokenHash) {
    final existingEntry = _tokenWriteTracking[uid]?[tokenHash];
    if (existingEntry != null) {
      existingEntry.pendingRegistrations++;
      return true;
    }

    var trackedHashCount = 0;
    for (final hashes in _tokenWriteTracking.values) {
      trackedHashCount += hashes.length;
    }
    if (trackedHashCount >= _maxTrackedTokenHashes) return false;

    final entry = _TokenWriteEntry()..pendingRegistrations = 1;
    _tokenWriteTracking.putIfAbsent(uid, () => {})[tokenHash] = entry;
    return true;
  }

  void _forgetPendingTokenHash(String uid, String tokenHash) {
    final entry = _tokenWriteTracking[uid]?[tokenHash];
    if (entry == null) return;
    if (entry.pendingRegistrations > 0) entry.pendingRegistrations--;
    _removeTokenEntryIfFinished(uid, tokenHash, entry);
  }

  void _removeTokenEntryIfFinished(
    String uid,
    String tokenHash,
    _TokenWriteEntry entry,
  ) {
    if (entry.pendingRegistrations != 0 || entry.write != null) return;
    final hashesForUid = _tokenWriteTracking[uid];
    if (hashesForUid == null || !identical(hashesForUid[tokenHash], entry)) {
      return;
    }
    hashesForUid.remove(tokenHash);
    if (hashesForUid.isEmpty) _tokenWriteTracking.remove(uid);
  }

  bool _isLoggingOut(String uid) => _loggingOutUidCounts.containsKey(uid);

  void _finishLogout(String uid) {
    final count = _loggingOutUidCounts[uid];
    if (count == null) return;
    if (count <= 1) {
      _loggingOutUidCounts.remove(uid);
    } else {
      _loggingOutUidCounts[uid] = count - 1;
    }
  }

  Future<void> _cleanupLogoutTokens(
    String uid,
    String? registeredTokenHash,
    int cleanupEpoch,
  ) async {
    final stopwatch = Stopwatch()..start();
    final entriesForUid = _tokenWriteTracking[uid];
    final pendingWrites =
        entriesForUid == null
            ? <Future<void>>[]
            : entriesForUid.values
                .map((entry) => entry.write)
                .whereType<Future<void>>()
                .toList();
    final tokenHashes = <String>{
      if (registeredTokenHash != null) registeredTokenHash,
      ...?entriesForUid?.keys,
    };

    // Reserve part of the existing logout bound for actual delete attempts.
    final writeWait = Duration(
      milliseconds: _cleanupTimeout.inMilliseconds ~/ 2,
    );
    if (pendingWrites.isNotEmpty) {
      try {
        final settledWrites = pendingWrites.map(
          (write) => write.then<void>(
            (_) {},
            onError: (Object error, StackTrace stackTrace) {
              _logError('FCM token write failed during logout cleanup', error);
            },
          ),
        );
        await Future.wait(settledWrites).timeout(writeWait);
      } on TimeoutException {
        _logDebug('FCM in-flight writes did not settle before logout cleanup.');
      }
    }

    for (final hash in tokenHashes) {
      if (!_isCurrentSession(uid, cleanupEpoch)) return;

      final remaining = _cleanupTimeout - stopwatch.elapsed;
      if (remaining <= Duration.zero) {
        // Start the owner-checked delete while still authenticated, but do not
        // extend logout beyond its cleanup deadline.
        unawaited(
          _deleteToken(uid, hash).catchError((Object error) {
            _logError(
              'FCM logout cleanup failed; sign-out will continue',
              error,
            );
          }),
        );
        continue;
      }

      try {
        await _deleteToken(uid, hash).timeout(remaining);
      } on TimeoutException {
        _logDebug('FCM logout cleanup timed out; sign-out will continue.');
      } catch (error) {
        _logError('FCM logout cleanup failed; sign-out will continue', error);
      }
    }
  }

  Future<void> _deleteToken(String uid, String tokenHash) async {
    if (FirebaseAuth.instance.currentUser?.uid != uid) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('fcmTokens')
        .doc(tokenHash)
        .delete()
        .timeout(_cleanupTimeout);
  }

  String _hashToken(String token) =>
      sha256.convert(utf8.encode(token)).toString();

  bool _isCurrentRegistration(String uid, int sessionEpoch) =>
      _isCurrentSession(uid, sessionEpoch) && !_isLoggingOut(uid);

  bool _isCurrentSession(String uid, int sessionEpoch) =>
      _isAndroid &&
      _sessionEpoch == sessionEpoch &&
      FirebaseAuth.instance.currentUser?.uid == uid;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  void _logDebug(String message) {
    if (kDebugMode) debugPrint(message);
  }

  void _logError(String message, [Object? error]) {
    if (kDebugMode) {
      final code = error is FirebaseException ? ' (${error.code})' : '';
      debugPrint('$message$code');
    }
  }
}
