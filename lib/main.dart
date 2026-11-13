import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/fcm_service.dart';
import 'services/notification_service.dart';
import 'services/chat_service.dart' as cs;
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await FcmService.instance.initialize();

  runApp(const AltrafloatApp());
}

// ============================================================
// ALTRAfloat APP
// ============================================================

class AltrafloatApp extends StatelessWidget {
  const AltrafloatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Altrafloat',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Arial',
        scaffoldBackgroundColor: const Color(0xFFF4FAFF),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0878E8)),
      ),
      home: const LoginPage(),
    );
  }
}

// ============================================================
// COLORS
// ============================================================

const Color blue = Color(0xFF0878E8);
const Color darkBlue = Color(0xFF064B9B);
const Color lightBlue = Color(0xFFE7F5FF);
const Color paleBlue = Color(0xFFF5FBFF);
const Color red = Color(0xFFF3213B);
const Color green = Color(0xFF24C875);
const Color darkText = Color(0xFF124A83);
const Color greyText = Color(0xFF6382A4);

class RegistrationIdValidator {
  static final RegExp _agentPattern = RegExp(r'^G7[0-9]{6,7}$');
  static final RegExp _loPattern = RegExp(r'^(S0|C0)[0-9]{6,7}$');

  static String normalize(String value) => value.trim().toUpperCase();

  static bool isValid(String value, {required bool isAgent}) {
    final id = normalize(value);
    return (isAgent ? _agentPattern : _loPattern).hasMatch(id);
  }

  static String errorMessage({required bool isAgent}) =>
      isAgent
          ? 'Agent ID must start with G7 followed by exactly 6 or 7 digits.'
          : 'L.O. ID must start with S0 or C0 followed by exactly 6 or 7 digits.';
}

class RegistrationIdAlreadyInUseException implements Exception {}

class RegistrationIdMismatchException implements Exception {}

class RegistrationIdFormatException implements Exception {}

class ProfileNotAuthorizedException implements Exception {}

class ProfileAwaitingAuthorizationException implements Exception {}

class AppStorage {
  static const String _profileKey = 'altrafloat_profile';
  static const String _chatKey = 'altrafloat_chat_messages';

  static DocumentReference<Map<String, dynamic>>? get _currentProfileRef {
    if (Firebase.apps.isEmpty) return null;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(user.uid);
  }

  static String _currentTime() {
    final now = DateTime.now();
    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final suffix = now.hour >= 12 ? 'PM' : 'AM';
    final minute = now.minute.toString().padLeft(2, '0');
    return '$hour:$minute $suffix';
  }

  static Future<void> saveProfile({
    required String username,
    required String email,
    required String role,
    required String id,
    required String category,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final normalizedId = RegistrationIdValidator.normalize(id);
    final isAgent = role == 'Agent';
    if (!RegistrationIdValidator.isValid(normalizedId, isAgent: isAgent)) {
      throw RegistrationIdFormatException();
    }

    final profileRef = _currentProfileRef;
    final profile = <String, dynamic>{
      'uid': profileRef?.id,
      'username': username,
      'email': email,
      'role': role,
      'id': normalizedId,
      'category': category,
    }..removeWhere((key, value) => value == null);

    if (profileRef != null) {
      final database = FirebaseFirestore.instance;
      final registrationIdRef = database
          .collection('registrationIds')
          .doc(normalizedId);
      var authorized = false;

      await database.runTransaction((transaction) async {
        final existingProfile = await transaction.get(profileRef);
        final registrationId = await transaction.get(registrationIdRef);
        final existingData = existingProfile.data();

        if (existingData != null &&
            (existingData['id'] != normalizedId ||
                existingData['role'] != role)) {
          throw RegistrationIdMismatchException();
        }

        final claimData = registrationId.data();
        if (registrationId.exists && claimData?['uid'] != profileRef.id) {
          throw RegistrationIdAlreadyInUseException();
        }
        if (registrationId.exists && claimData?['role'] != role) {
          throw RegistrationIdAlreadyInUseException();
        }

        authorized = existingData?['authorized'] == true;

        if (!registrationId.exists) {
          transaction.set(registrationIdRef, {
            'uid': profileRef.id,
            'role': role,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        transaction.set(profileRef, {
          ...profile,
          'authorized': authorized,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });

      profile['authorized'] = authorized.toString();
    } else {
      profile['authorized'] = 'false';
    }

    await prefs.setString(_profileKey, jsonEncode(profile));
  }

  static Future<Map<String, String>?> loadAuthorizedProfile({
    required String role,
    String? id,
    bool distinguishPendingAuthorization = false,
  }) async {
    final profileRef = _currentProfileRef;
    if (profileRef == null ||
        (role != 'Agent' && role != 'Liquidity Officer')) {
      return null;
    }

    final snapshot = await profileRef.get(
      const GetOptions(source: Source.server),
    );
    final data = snapshot.data();
    if (!snapshot.exists ||
        !matchesProfile(data, uid: profileRef.id, role: role, id: id)) {
      return null;
    }
    if (role == 'Liquidity Officer' && data?['authorized'] != true) {
      if (distinguishPendingAuthorization) {
        throw ProfileAwaitingAuthorizationException();
      }
      return null;
    }

    return {
      for (final key in [
        'username',
        'email',
        'role',
        'id',
        'category',
        'authorized',
      ])
        if (data != null && data[key] != null) key: data[key].toString(),
    };
  }

  static bool isAuthorizedProfile(
    Map<String, dynamic>? data, {
    required String uid,
    required String role,
    String? id,
  }) =>
      matchesProfile(data, uid: uid, role: role, id: id) &&
      (role == 'Agent' || data?['authorized'] == true);

  static bool matchesProfile(
    Map<String, dynamic>? data, {
    required String uid,
    required String role,
    String? id,
  }) {
    if (data == null || (role != 'Agent' && role != 'Liquidity Officer')) {
      return false;
    }

    final profileId = data['id'];
    return data['uid'] == uid &&
        data['role'] == role &&
        profileId is String &&
        RegistrationIdValidator.isValid(profileId, isAgent: role == 'Agent') &&
        (id == null ||
            RegistrationIdValidator.normalize(profileId) ==
                RegistrationIdValidator.normalize(id));
  }

  static Future<Map<String, String>> loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final profileRef = _currentProfileRef;
    if (profileRef != null) {
      try {
        final snapshot = await profileRef.get();
        final data = snapshot.data();
        if (data != null) {
          final profile = {
            for (final key in [
              'username',
              'email',
              'role',
              'id',
              'category',
              'authorized',
            ])
              if (data[key] != null) key: data[key].toString(),
          };
          await prefs.setString(_profileKey, jsonEncode(profile));
          return profile;
        }
      } on FirebaseException {
        // Keep the locally cached profile available when Firestore is offline.
      }
    }

    final saved = prefs.getString(_profileKey);
    if (saved == null || saved.isEmpty) {
      return {
        'username': 'Altrafloat User',
        'email': '',
        'role': 'Agent',
        'id': '',
        'category': 'Main Agent',
      };
    }

    try {
      final decoded = jsonDecode(saved);
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
        );
      }
    } catch (_) {}

    return {
      'username': 'Altrafloat User',
      'email': '',
      'role': 'Agent',
      'id': '',
      'category': 'Main Agent',
    };
  }

  static Future<void> saveChatMessages(
    List<Map<String, String>> messages,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chatKey, jsonEncode(messages));
  }

  static Future<List<Map<String, String>>> loadChatMessages() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_chatKey);
    if (saved == null || saved.isEmpty) return [];

    try {
      final decoded = jsonDecode(saved);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map(
              (item) => item.map(
                (key, value) =>
                    MapEntry(key.toString(), value?.toString() ?? ''),
              ),
            )
            .toList();
      }
    } catch (_) {}

    return [];
  }

  static Future<void> appendChatMessage(Map<String, String> message) async {
    final list = await loadChatMessages();
    list.add(message);
    await saveChatMessages(list);
  }

  static Stream<List<Map<String, dynamic>>> watchAgentRequests(String uid) =>
      _watchRequests('agentUid', uid);

  static Stream<List<Map<String, dynamic>>> watchLORequests(String uid) =>
      _watchRequests('loUid', uid);

  static Stream<List<Map<String, dynamic>>> _watchRequests(
    String ownerField,
    String uid,
  ) {
    return FirebaseFirestore.instance
        .collection('requests')
        .where(ownerField, isEqualTo: uid)
        .snapshots()
        .map((snapshot) {
          final requests =
              snapshot.docs.map((document) {
                final request = document.data();
                final agentName = request['agentName']?.toString() ?? 'Agent';
                final createdAt = request['createdAt'];
                request['_documentId'] = document.id;
                request['name'] = agentName;
                request['id'] = request['agentId']?.toString() ?? '';
                request['letter'] =
                    agentName.isEmpty ? 'A' : agentName[0].toUpperCase();
                request['time'] =
                    createdAt is Timestamp ? _formatRequestTime(createdAt) : '';
                return request;
              }).toList();
          requests.sort(
            (first, second) => _requestDate(
              second['createdAt'],
            ).compareTo(_requestDate(first['createdAt'])),
          );
          return requests;
        });
  }

  static DateTime _requestDate(dynamic value) =>
      value is Timestamp
          ? value.toDate()
          : DateTime.fromMillisecondsSinceEpoch(0);

  static String _formatRequestTime(Timestamp timestamp) {
    final date = timestamp.toDate().toLocal();
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final suffix = date.hour >= 12 ? 'PM' : 'AM';
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute $suffix';
  }

  static Stream<List<Map<String, dynamic>>> watchAvailableLOs() {
    return FirebaseFirestore.instance
        .collection('loAvailability')
        .where('available', isEqualTo: true)
        .where('role', isEqualTo: 'Liquidity Officer')
        .where('authorized', isEqualTo: true)
        .where('idValid', isEqualTo: true)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((document) => document.data()).toList()..sort(
                (first, second) => (first['name'] ?? '').toString().compareTo(
                  (second['name'] ?? '').toString(),
                ),
              ),
        );
  }

  static Future<void> ensureLOAvailability(Map<String, String> profile) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('A signed-in LO is required.');

    final availabilityRef = FirebaseFirestore.instance
        .collection('loAvailability')
        .doc(user.uid);
    final username = profile['username'] ?? '';
    final id = profile['id'] ?? '';

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final snapshot = await transaction.get(availabilityRef);
      if (!snapshot.exists) {
        transaction.set(availabilityRef, {
          'uid': user.uid,
          'role': 'Liquidity Officer',
          'name': username,
          'id': id,
          'idValid': true,
          'available': false,
          'authorized': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        final existing = snapshot.data()!;
        if (existing['uid'] != user.uid ||
            existing['role'] != 'Liquidity Officer' ||
            existing['id'] != id ||
            existing['idValid'] != true ||
            existing['authorized'] != true ||
            existing['createdAt'] is! Timestamp) {
          throw StateError(
            'LO availability projection is incomplete. Ask an administrator to migrate it.',
          );
        }
        if (existing['name'] != username) {
          transaction.update(availabilityRef, {
            'name': username,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      }
    });
  }

  static Stream<bool> watchLOAvailability(String uid) {
    return FirebaseFirestore.instance
        .collection('loAvailability')
        .doc(uid)
        .snapshots()
        .map((snapshot) => snapshot.data()?['available'] == true);
  }

  static Future<void> setLOAvailability({
    required Map<String, String> profile,
    required bool available,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('A signed-in LO is required.');

    await FirebaseFirestore.instance
        .collection('loAvailability')
        .doc(user.uid)
        .update({
          'available': available,
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  static Future<void> createRequest({
    required String loUid,
    required String loName,
    required String loId,
    required String type,
    required String amount,
    required String message,
    required Map<String, String> agentProfile,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('A signed-in Agent is required.');

    await FirebaseFirestore.instance.collection('requests').add({
      'agentUid': user.uid,
      'agentName': agentProfile['username'] ?? '',
      'agentId': agentProfile['id'] ?? '',
      'loUid': loUid,
      'loName': loName,
      'loId': loId,
      'type': type,
      'amount': amount,
      'message': message,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> updateRequestStatus({
    required String documentId,
    required String status,
    String? declineReason,
  }) async {
    final updates = <String, dynamic>{
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (declineReason != null) updates['declineReason'] = declineReason;

    await FirebaseFirestore.instance
        .collection('requests')
        .doc(documentId)
        .update(updates);
  }
}

// ============================================================
// LOGIN PAGE
// ============================================================

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool isAgent = true;
  bool obscurePassword = true;
  bool isLoggingIn = false;
  bool acceptedPrivacyPolicy = false;
  bool acceptedTerms = false;

  static const String privacyPolicyVersion = '1.0';
  static const String termsVersion = '1.0';

  final TextEditingController usernameController = TextEditingController();

  final TextEditingController emailController = TextEditingController();

  final TextEditingController idController = TextEditingController();

  final TextEditingController categoryController = TextEditingController();

  final TextEditingController passwordController = TextEditingController();

  @override
  void dispose() {
    usernameController.dispose();
    emailController.dispose();
    idController.dispose();
    categoryController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  // ============================================================
  // FIREBASE LOGIN
  // ============================================================

  Future<void> login() async {
    final username = usernameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final userId = idController.text.trim();
    if (!acceptedPrivacyPolicy || !acceptedTerms) {
      _showMessage(
        'Please accept the Privacy Policy and Terms before logging in.',
      );
      return;
    }
    // BASIC VALIDATION
    if (email.isEmpty) {
      _showMessage('Please enter your email address.');
      return;
    }

    if (password.isEmpty) {
      _showMessage('Please enter your password.');
      return;
    }

    setState(() {
      isLoggingIn = true;
    });

    try {
      // SIGN IN WITH FIREBASE
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      final signedInUser = FirebaseAuth.instance.currentUser;

      if (signedInUser == null) {
        throw FirebaseAuthException(code: 'user-not-found');
      }

      // SAVE PRIVACY POLICY AND TERMS ACCEPTANCE
      try {
        await FirebaseFirestore.instance
            .collection('policyAcceptances')
            .doc(signedInUser.uid)
            .set({
          'uid': signedInUser.uid,
          'privacyPolicyVersion': privacyPolicyVersion,
          'termsVersion': termsVersion,
          'acceptedAt': FieldValue.serverTimestamp(),
        });
      } on FirebaseException catch (error) {
        _logLoginFirestoreFailure('policy_acceptance_write', error);
        await FcmService.instance.signOut();
        if (!mounted) return;
        _showMessage(
          'Could not save your Privacy Policy and Terms acceptance. '
          'Please try again.',
        );
        return;
      }
      // CHECK THE SERVER-ASSIGNED AI MANAGER CLAIM
      final tokenResult = await signedInUser.getIdTokenResult(true);

      if (tokenResult.claims?['aiManager'] == true) {
        if (!mounted) return;

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AIManagerDashboard()),
        );
        return;
      }

      // NORMAL AGENT AND LIQUIDITY OFFICER VALIDATION
      if (username.isEmpty) {
        await FcmService.instance.signOut();
        if (!mounted) return;
        _showMessage('Please enter your user name.');
        return;
      }

      if (userId.isEmpty) {
        await FcmService.instance.signOut();
        if (!mounted) return;
        _showMessage(
          isAgent ? 'Please enter your Agent ID.' : 'Please enter your LO ID.',
        );
        return;
      }

      if (!RegistrationIdValidator.isValid(userId, isAgent: isAgent)) {
        await FcmService.instance.signOut();
        if (!mounted) return;
        _showMessage(RegistrationIdValidator.errorMessage(isAgent: isAgent));
        return;
      }

      if (isAgent && categoryController.text.trim().isEmpty) {
        await FcmService.instance.signOut();
        if (!mounted) return;
        _showMessage('Please select your Agent Category.');
        return;
      }

      // LOAD AND VERIFY THE AUTHORIZED PROFILE
      final role = isAgent ? 'Agent' : 'Liquidity Officer';

      Map<String, String>? profile;
      try {
        profile = await AppStorage.loadAuthorizedProfile(
          role: role,
          id: RegistrationIdValidator.normalize(userId),
          distinguishPendingAuthorization: true,
        );
      } on FirebaseException catch (error) {
        _logLoginFirestoreFailure('profile_authorization_read', error);
        await FcmService.instance.signOut();
        if (!mounted) return;
        _showMessage(
          'Could not read and verify your authorization profile. '
          'Please try again.',
        );
        return;
      }

      if (profile == null) {
        await FcmService.instance.signOut();
        throw ProfileNotAuthorizedException();
      }

      if (!mounted) return;

      // OPEN THE CORRECT DASHBOARD
      if (isAgent) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AgentDashboard()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LiquidityOfficerDashboard()),
        );
      }
    } on RegistrationIdAlreadyInUseException {
      await FcmService.instance.signOut();
      if (!mounted) return;

      _showMessage(
        'This ID is already registered to another account. Please check the ID you entered.',
      );
    } on RegistrationIdMismatchException {
      await FcmService.instance.signOut();
      if (!mounted) return;

      _showMessage('The registration ID or account type does not match.');
    } on ProfileAwaitingAuthorizationException {
      await FcmService.instance.signOut();
      if (!mounted) return;

      _showMessage(
        'Your account has been created and is awaiting authorization. '
        'You can sign in to the dashboard after approval.',
      );
    } on ProfileNotAuthorizedException {
      await FcmService.instance.signOut();
      if (!mounted) return;

      _showMessage(
        'The account profile could not be found or does not match the selected role and ID.',
      );
    } on FirebaseAuthException catch (e) {
      await FcmService.instance.signOut();
      if (!mounted) return;

      String message;

      switch (e.code) {
        case 'invalid-credential':
          message = 'Incorrect email or password. Please check your details.';
          break;
        case 'user-not-found':
          message = 'No account was found for this email address.';
          break;
        case 'wrong-password':
          message = 'Incorrect password. Please try again.';
          break;
        case 'invalid-email':
          message = 'Please enter a valid email address.';
          break;
        case 'user-disabled':
          message =
              'This account has been disabled. Please contact Altrafloat support.';
          break;
        case 'too-many-requests':
          message =
              'Too many login attempts. Please wait a moment and try again.';
          break;
        case 'network-request-failed':
          message =
              'Network connection failed. Please check your internet connection.';
          break;
        default:
          message =
              'Unable to sign in. Please check your details and try again.';
      }

      _showMessage(message);
    } on FirebaseException {
      await FcmService.instance.signOut();
      if (!mounted) return;

      _showMessage(
        'Unable to verify your authorization. Please try again when connected.',
      );
    } catch (e) {
      await FcmService.instance.signOut();
      if (!mounted) return;

      _showMessage('Something went wrong while signing in. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          isLoggingIn = false;
        });
      }
    }
  }

  Future<void> resetPassword() async {
    final email = emailController.text.trim();

    if (email.isEmpty) {
      _showMessage('Please enter your email address first.');
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);

      if (!mounted) return;
      _showMessage('Password reset email sent to $email');
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      switch (e.code) {
        case 'invalid-email':
          _showMessage('Please enter a valid email address.');
          break;
        case 'user-not-found':
          _showMessage('No account was found for this email address.');
          break;
        default:
          _showMessage(
            'Unable to send a password reset email. Please try again.',
          );
      }
    } catch (_) {
      if (!mounted) return;
      _showMessage('Something went wrong while sending the reset email.');
    }
  }
  // ============================================================
  // MESSAGE
  // ============================================================
  void _logLoginFirestoreFailure(
  String operation,
  FirebaseException error,
) {
  if (kDebugMode) {
    debugPrint(
      'Login Firestore failure: operation=$operation '
      'code=${error.code} plugin=${error.plugin} '
      'message=${error.message ?? 'No message'}',
    );
  }
}
  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: darkBlue,
          duration: const Duration(seconds: 4),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFDDF3FF), Color(0xFFF8FCFF), Color(0xFFD9F0FF)],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 24,
                      ),
                      child: Column(
                        children: [
                          const SizedBox(height: 8),
                          const AltrafloatBrand(large: true),
                          const SizedBox(height: 24),
                          CheckboxListTile(
                            value: acceptedPrivacyPolicy,
                            onChanged: (value) {
                              setState(
                                () => acceptedPrivacyPolicy = value ?? false,
                              );
                            },
                            title: const Text('I accept the Privacy Policy'),
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                          ),

                          CheckboxListTile(
                            value: acceptedTerms,
                            onChanged: (value) {
                              setState(() => acceptedTerms = value ?? false);
                            },
                            title: const Text(
                              'I accept the Terms and Conditions',
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                          ),

                          const SizedBox(height: 22),

                          // LOGIN CARD
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(28, 34, 28, 28),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: .96),
                              borderRadius: BorderRadius.circular(34),
                              boxShadow: [
                                BoxShadow(
                                  color: blue.withValues(alpha: .12),
                                  blurRadius: 35,
                                  offset: const Offset(0, 15),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Center(
                                  child: Column(
                                    children: [
                                      Text(
                                        'Welcome Back',
                                        style: TextStyle(
                                          fontSize:
                                              constraints.maxWidth > 600
                                                  ? 44
                                                  : 34,
                                          fontWeight: FontWeight.w800,
                                          color: darkBlue,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      const Text(
                                        'Sign in to your Altrafloat account',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 17,
                                          color: greyText,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 28),

                                // ROLE SELECTOR
                                Container(
                                  height: 64,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFEAF6FF),
                                    borderRadius: BorderRadius.circular(34),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              isAgent = true;
                                            });
                                          },
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                              milliseconds: 200,
                                            ),
                                            margin: const EdgeInsets.all(3),
                                            decoration: BoxDecoration(
                                              gradient:
                                                  isAgent
                                                      ? const LinearGradient(
                                                        colors: [
                                                          Color(0xFF086BE0),
                                                          Color(0xFF25A0F5),
                                                        ],
                                                      )
                                                      : null,
                                              borderRadius:
                                                  BorderRadius.circular(32),
                                              boxShadow:
                                                  isAgent
                                                      ? [
                                                        BoxShadow(
                                                          color: blue
                                                              .withValues(
                                                                alpha: .25,
                                                              ),
                                                          blurRadius: 12,
                                                        ),
                                                      ]
                                                      : null,
                                            ),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.person,
                                                  color:
                                                      isAgent
                                                          ? Colors.white
                                                          : darkBlue,
                                                ),
                                                const SizedBox(width: 10),
                                                Text(
                                                  'Agent',
                                                  style: TextStyle(
                                                    fontSize: 17,
                                                    fontWeight: FontWeight.bold,
                                                    color:
                                                        isAgent
                                                            ? Colors.white
                                                            : darkBlue,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                        child: GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              isAgent = false;
                                            });
                                          },
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                              milliseconds: 200,
                                            ),
                                            margin: const EdgeInsets.all(3),
                                            decoration: BoxDecoration(
                                              gradient:
                                                  !isAgent
                                                      ? const LinearGradient(
                                                        colors: [
                                                          Color(0xFF086BE0),
                                                          Color(0xFF25A0F5),
                                                        ],
                                                      )
                                                      : null,
                                              borderRadius:
                                                  BorderRadius.circular(32),
                                            ),
                                            child: Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(
                                                  Icons.shield_outlined,
                                                  color:
                                                      !isAgent
                                                          ? Colors.white
                                                          : darkBlue,
                                                ),
                                                const SizedBox(width: 8),
                                                Flexible(
                                                  child: Text(
                                                    'Liquidity Officer',
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color:
                                                          !isAgent
                                                              ? Colors.white
                                                              : darkBlue,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 24),

                                // USER NAME
                                _LoginField(
                                  icon: Icons.person_outline,
                                  label: 'User Name',
                                  hint: 'Enter your user name',
                                  controller: usernameController,
                                ),

                                const SizedBox(height: 14),

                                // EMAIL
                                _LoginField(
                                  icon: Icons.email_outlined,
                                  label: 'Email Address',
                                  hint: 'Enter your email address',
                                  controller: emailController,
                                  keyboardType: TextInputType.emailAddress,
                                ),

                                const SizedBox(height: 14),

                                // ID
                                _LoginField(
                                  icon: Icons.badge_outlined,
                                  label: isAgent ? 'Agent ID' : 'LO ID',
                                  hint:
                                      isAgent
                                          ? 'Example: G7123456'
                                          : 'Example: S0123456 or C0123456',
                                  controller: idController,
                                ),

                                // CATEGORY FOR AGENT
                                if (isAgent) ...[
                                  const SizedBox(height: 14),
                                  GestureDetector(
                                    onTap: () {
                                      showModalBottomSheet(
                                        context: context,
                                        shape: const RoundedRectangleBorder(
                                          borderRadius: BorderRadius.vertical(
                                            top: Radius.circular(25),
                                          ),
                                        ),
                                        builder: (_) {
                                          return SafeArea(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const SizedBox(height: 15),
                                                const Text(
                                                  'Select Agent Category',
                                                  style: TextStyle(
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.bold,
                                                    color: darkBlue,
                                                  ),
                                                ),
                                                const SizedBox(height: 10),
                                                for (final category in [
                                                  'Main Agent',
                                                  'Cash Agent',
                                                  'Airtime Agent',
                                                  'Mobile Money Agent',
                                                ])
                                                  ListTile(
                                                    leading: const Icon(
                                                      Icons.grid_view_rounded,
                                                      color: blue,
                                                    ),
                                                    title: Text(category),
                                                    onTap: () {
                                                      categoryController.text =
                                                          category;
                                                      Navigator.pop(context);
                                                      setState(() {});
                                                    },
                                                  ),
                                                const SizedBox(height: 15),
                                              ],
                                            ),
                                          );
                                        },
                                      );
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 18,
                                        vertical: 14,
                                      ),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: const Color(0xFFC9E2F5),
                                          width: 1.5,
                                        ),
                                        borderRadius: BorderRadius.circular(17),
                                        color: Colors.white,
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.grid_view_rounded,
                                            color: darkBlue,
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  'Agent Category',
                                                  style: TextStyle(
                                                    color: darkBlue,
                                                    fontSize: 15,
                                                  ),
                                                ),
                                                const SizedBox(height: 3),
                                                Text(
                                                  categoryController
                                                          .text
                                                          .isEmpty
                                                      ? 'Select Agent Category'
                                                      : categoryController.text,
                                                  style: const TextStyle(
                                                    color: greyText,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const Icon(
                                            Icons.keyboard_arrow_down,
                                            color: darkBlue,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],

                                const SizedBox(height: 14),

                                // PASSWORD
                                Container(
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: const Color(0xFFC9E2F5),
                                      width: 1.5,
                                    ),
                                    borderRadius: BorderRadius.circular(17),
                                    color: Colors.white,
                                  ),
                                  child: TextField(
                                    controller: passwordController,
                                    obscureText: obscurePassword,
                                    decoration: InputDecoration(
                                      prefixIcon: const Icon(
                                        Icons.lock_outline,
                                        color: darkBlue,
                                      ),
                                      labelText: 'Password',
                                      hintText: 'Enter your password',
                                      labelStyle: const TextStyle(
                                        color: darkBlue,
                                      ),
                                      border: InputBorder.none,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            vertical: 18,
                                          ),
                                      suffixIcon: IconButton(
                                        onPressed: () {
                                          setState(() {
                                            obscurePassword = !obscurePassword;
                                          });
                                        },
                                        icon: Icon(
                                          obscurePassword
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                          color: darkBlue,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 22),

                                // LOGIN
                                SizedBox(
                                  width: double.infinity,
                                  height: 60,
                                  child: ElevatedButton(
                                    onPressed: isLoggingIn ? null : login,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: blue,
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor: blue.withValues(
                                        alpha: .55,
                                      ),
                                      elevation: 5,
                                      shadowColor: blue.withValues(alpha: .35),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                    ),
                                    child:
                                        isLoggingIn
                                            ? const SizedBox(
                                              width: 26,
                                              height: 26,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 3,
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                      Color
                                                    >(Colors.white),
                                              ),
                                            )
                                            : const Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  'Login',
                                                  style: TextStyle(
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                SizedBox(width: 16),
                                                Icon(
                                                  Icons.arrow_forward,
                                                  size: 28,
                                                ),
                                              ],
                                            ),
                                  ),
                                ),

                                const SizedBox(height: 22),

                                Center(
                                  child: TextButton(
                                    onPressed: resetPassword,
                                    child: const Text(
                                      'Forgot Password?',
                                      style: TextStyle(
                                        color: blue,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 4),

                                Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        height: 1,
                                        color: const Color(0xFFBCD7EA),
                                      ),
                                    ),
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 15,
                                      ),
                                      child: Text(
                                        'OR',
                                        style: TextStyle(
                                          color: greyText,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Container(
                                        height: 1,
                                        color: const Color(0xFFBCD7EA),
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 16),

                                GestureDetector(
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder:
                                            (_) => const CreateAccountPage(),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 15,
                                    ),
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: const Color(0xFFC9E2F5),
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: RichText(
                                      textAlign: TextAlign.center,
                                      text: const TextSpan(
                                        style: TextStyle(
                                          color: greyText,
                                          fontSize: 15,
                                        ),
                                        children: [
                                          TextSpan(
                                            text: 'Don’t have an account?  ',
                                          ),
                                          TextSpan(
                                            text: 'Create Account',
                                            style: TextStyle(
                                              color: blue,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 20),

                                const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.lock, size: 20, color: blue),
                                    SizedBox(width: 8),
                                    Text(
                                      'Secure  •  Reliable  •  Altrafloat',
                                      style: TextStyle(
                                        color: blue,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 15),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ============================================================
// LOGIN FIELD
// ============================================================

class _LoginField extends StatelessWidget {
  final IconData icon;
  final String label;
  final String hint;
  final TextEditingController controller;
  final TextInputType keyboardType;

  const _LoginField({
    required this.icon,
    required this.label,
    required this.hint,
    required this.controller,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFC9E2F5), width: 1.5),
        borderRadius: BorderRadius.circular(17),
        color: Colors.white,
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        autocorrect: false,
        enableSuggestions: keyboardType == TextInputType.emailAddress,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: darkBlue),
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(color: darkBlue),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 18),
        ),
      ),
    );
  }
}

// ============================================================
// ALTRAfloat BRAND
// ============================================================

class AltrafloatBrand extends StatelessWidget {
  final bool large;

  const AltrafloatBrand({super.key, this.large = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: large ? 62 : 45,
              height: large ? 62 : 45,
              decoration: BoxDecoration(
                color: blue,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: blue.withValues(alpha: .25),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(Icons.more_horiz, color: Colors.white, size: 34),
                  Positioned(
                    bottom: 4,
                    left: 9,
                    child: CustomPaint(
                      size: const Size(14, 10),
                      painter: _TrianglePainter(),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: large ? 48 : 25,
                  fontWeight: FontWeight.w900,
                ),
                children: const [
                  TextSpan(text: 'Altra', style: TextStyle(color: darkBlue)),
                  TextSpan(text: 'float', style: TextStyle(color: red)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Agent & Liquidity Officer Communication',
          style: TextStyle(
            color: const Color(0xFF52749C),
            fontSize: large ? 17 : 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _TrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = red
          ..style = PaintingStyle.fill;

    final path =
        Path()
          ..moveTo(0, 0)
          ..lineTo(size.width, 0)
          ..lineTo(0, size.height)
          ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

Widget _dashboardAccessPage(
  BuildContext context, {
  required String role,
  required bool isVerifying,
  required bool verificationFailed,
}) {
  return Scaffold(
    appBar: AppBar(title: Text('$role Dashboard')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child:
            isVerifying
                ? const CircularProgressIndicator()
                : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      verificationFailed
                          ? 'Authorization could not be verified. Please sign in again while connected.'
                          : 'This account is not authorized to access the $role dashboard.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () async {
                        if (Firebase.apps.isNotEmpty) {
                          await FcmService.instance.signOut();
                        }
                        if (!context.mounted) return;
                        Navigator.pushAndRemoveUntil(
                          context,
                          MaterialPageRoute(builder: (_) => const LoginPage()),
                          (route) => false,
                        );
                      },
                      child: const Text('Return to sign in'),
                    ),
                  ],
                ),
      ),
    ),
  );
}

// ============================================================
// AGENT DASHBOARD
// ============================================================

class AgentDashboard extends StatefulWidget {
  const AgentDashboard({super.key});

  @override
  State<AgentDashboard> createState() => _AgentDashboardState();
}

class _AgentDashboardState extends State<AgentDashboard> {
  int selectedIndex = 0;
  bool _checkingAuthorization = true;
  bool _isAuthorized = false;
  bool _authorizationVerificationFailed = false;
  String? _dashboardDataError;
  Map<String, String> profile = {
    'username': 'Altrafloat User',
    'email': '',
    'role': 'Agent',
    'id': '',
    'category': 'Main Agent',
  };

  List<Map<String, dynamic>> requests = [];
  List<Map<String, dynamic>> availableOfficers = [];
  StreamSubscription<List<Map<String, dynamic>>>? _requestsSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _officersSubscription;

  @override
  void initState() {
    super.initState();
    _loadDashboardState();
  }

  Future<void> _loadDashboardState() async {
    try {
      final savedProfile = await AppStorage.loadAuthorizedProfile(
        role: 'Agent',
      );
      if (savedProfile == null) {
        if (Firebase.apps.isNotEmpty &&
            FirebaseAuth.instance.currentUser != null) {
          await FcmService.instance.signOut();
        }
        if (!mounted) return;
        setState(() => _checkingAuthorization = false);
        return;
      }

      if (!mounted) return;
      setState(() {
        profile = savedProfile;
        _isAuthorized = true;
        _checkingAuthorization = false;
      });

      await _requestsSubscription?.cancel();
      await _officersSubscription?.cancel();
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      _requestsSubscription = AppStorage.watchAgentRequests(uid).listen(
        (savedRequests) {
          if (!mounted) return;
          setState(() {
            requests = savedRequests;
            _dashboardDataError = null;
          });
        },
        onError: (Object error, StackTrace stackTrace) {
          _showDashboardDataError('Could not load your requests.');
        },
      );
      _officersSubscription = AppStorage.watchAvailableLOs().listen(
        (officers) {
          if (!mounted) return;
          setState(() {
            availableOfficers = officers;
            _dashboardDataError = null;
          });
        },
        onError: (Object error, StackTrace stackTrace) {
          if (kDebugMode) {
            if (error is FirebaseException) {
              debugPrint(
                'Available LO query failed (${error.code}): ${error.message}',
              );
            } else {
              debugPrint('Available LO query failed: $error');
            }
            debugPrintStack(stackTrace: stackTrace);
          }
          _showDashboardDataError('Could not load available LOs.');
        },
      );
    } on FirebaseException {
      if (Firebase.apps.isNotEmpty &&
          FirebaseAuth.instance.currentUser != null) {
        await FcmService.instance.signOut();
      }
      if (!mounted) return;
      setState(() {
        _checkingAuthorization = false;
        _authorizationVerificationFailed = true;
      });
    }
  }

  void _showDashboardDataError(String message) {
    if (!mounted) return;
    setState(() => _dashboardDataError = message);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _requestsSubscription?.cancel();
    _officersSubscription?.cancel();
    super.dispose();
  }

  Future<void> _confirmLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to log out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );

    if (shouldLogout != true) return;

    await FcmService.instance.signOut();
    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  Future<void> _openNewRequestDialog({
    Map<String, dynamic>? selectedOfficer,
  }) async {
    if (availableOfficers.isEmpty) {
      _showDashboardDataError('No LOs are currently available.');
      return;
    }

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        return _NewRequestDialog(
          availableOfficers: availableOfficers,
          selectedOfficer: selectedOfficer,
          onCancel: () => Navigator.pop(dialogContext),
          onSend: (result) => Navigator.pop(dialogContext, result),
        );
      },
    );

    if (result == null) return;

    if (result['amount']!.isEmpty) {
      _showDashboardDataError('Enter an amount for the request.');
      return;
    }

    final officer = availableOfficers.cast<Map<String, dynamic>?>().firstWhere(
      (item) => item?['uid'] == result['loUid'],
      orElse: () => null,
    );
    if (officer == null) {
      _showDashboardDataError(
        'That LO is no longer available. Choose another LO.',
      );
      return;
    }

    try {
      await AppStorage.createRequest(
        loUid: officer['uid'].toString(),
        loName: officer['name'].toString(),
        loId: officer['id'].toString(),
        type: result['type']!,
        amount: result['amount']!,
        message: result['message']!,
        agentProfile: profile,
      );
    } on FirebaseException {
      _showDashboardDataError('Could not send the request. Please try again.');
    }
  }

  Future<void> _cancelRequest(Map<String, dynamic> request) async {
    try {
      await AppStorage.updateRequestStatus(
        documentId: request['_documentId'].toString(),
        status: 'cancelled',
      );
    } on FirebaseException {
      _showDashboardDataError('Could not cancel this request.');
    }
  }

  Future<void> _openProfilePage() async {
    final saved = await AppStorage.loadProfile();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _ProfileDetailsPage(profile: saved)),
    );
    _loadDashboardState();
  }

  void _openNotificationsPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationListPage()),
    );
  }

  Future<void> _openSettingsPage() async {
    final saved = await AppStorage.loadProfile();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _SettingsPage(profile: saved)),
    );
    _loadDashboardState();
  }

  void _openChatPage() {
    setState(() => selectedIndex = 2);
  }

  Future<void> _openConversationForRequest(Map<String, dynamic> request) async {
    final status = request['status']?.toString();
    if (status != 'accepted') {
      _showDashboardDataError('Chat is only available for accepted requests.');
      return;
    }

    final requestId = request['_documentId']?.toString();
    final agentUid = request['agentUid']?.toString();
    final loUid = request['loUid']?.toString();
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    if (requestId == null ||
        agentUid == null ||
        loUid == null ||
        currentUid == null) {
      _showDashboardDataError('Unable to open chat: missing credentials.');
      return;
    }

    if (currentUid != agentUid) {
      _showDashboardDataError('You are not authorized for this conversation.');
      return;
    }

    try {
      await cs.ChatService.instance.ensureConversation(requestId);
    } on cs.ChatServiceException catch (e) {
      _showDashboardDataError(
        'Could not start conversation (${e.failure.name}).',
      );
      return;
    } catch (_) {
      _showDashboardDataError('Could not start conversation.');
      return;
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => ChatPage(
              currentUser: profile['username'] ?? 'Agent',
              currentRole: 'Agent',
              otherUser: request['loName']?.toString() ?? 'Liquidity Officer',
              otherRole: 'Liquidity Officer',
              chatId: requestId,
              currentUid: currentUid,
              counterpartUid: loUid,
            ),
      ),
    );
  }

  int _requestCount(String status) =>
      requests.where((request) => request['status'] == status).length;

  @override
  Widget build(BuildContext context) {
    if (!_isAuthorized) {
      return _dashboardAccessPage(
        context,
        role: 'Agent',
        isVerifying: _checkingAuthorization,
        verificationFailed: _authorizationVerificationFailed,
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF2F9FE),
      appBar: _dashboardAppBar(
        context,
        role: (profile['role'] ?? 'AGENT').toUpperCase(),
        onProfile: _openProfilePage,
        onNotifications: _openNotificationsPage,
      ),
      body: SafeArea(child: _agentBody()),
      bottomNavigationBar: _agentNavigation(),
    );
  }

  Widget _agentBody() {
    if (selectedIndex == 1) {
      return _requestsPage();
    }
    if (selectedIndex == 2) {
      return _conversationsPage();
    }
    if (selectedIndex == 3) {
      return _morePage();
    }
    return _agentHome();
  }

  PreferredSizeWidget _dashboardAppBar(
    BuildContext context, {
    required String role,
    required VoidCallback onProfile,
    required VoidCallback onNotifications,
  }) {
    return AppBar(
      backgroundColor: const Color(0xFFF2F9FE),
      elevation: 0,
      centerTitle: false,
      leading: IconButton(
        icon: const Icon(Icons.menu, color: darkBlue, size: 28),
        onPressed: () {},
      ),
      titleSpacing: 0,
      title: const AltrafloatBrand(),
      actions: [
        IconButton(
          onPressed: onNotifications,
          icon: const Icon(Icons.notifications_none, color: darkBlue, size: 28),
        ),
        IconButton(
          onPressed: _confirmLogout,
          icon: const Icon(Icons.logout, color: darkBlue, size: 26),
          tooltip: 'Logout',
        ),
        IconButton(
          onPressed: onProfile,
          icon: const CircleAvatar(
            radius: 18,
            backgroundColor: Color(0xFFDDF0FF),
            child: Icon(Icons.person, color: darkBlue),
          ),
        ),
        const SizedBox(width: 5),
      ],
    );
  }

  Widget _requestsPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'My Requests',
          style: TextStyle(
            color: darkBlue,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        if (requests.isEmpty)
          const Text('No requests yet.')
        else
          ...requests.map(
            (request) => _whiteCard(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _Avatar(
                    letter:
                        (request['letter'] ?? 'A')
                            .toString()
                            .substring(0, 1)
                            .toUpperCase(),
                    size: 42,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          request['type']?.toString() ?? 'Request',
                          style: const TextStyle(
                            color: darkBlue,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${request['amount'] ?? ''} • ${request['status'] ?? 'pending'}\nTo: ${request['loName'] ?? 'Liquidity Officer'}',
                          style: const TextStyle(color: greyText, fontSize: 12),
                        ),
                        if (request['declineReason'] is String &&
                            (request['declineReason'] as String).isNotEmpty)
                          Text(
                            'Reason: ${request['declineReason']}',
                            style: const TextStyle(
                              color: greyText,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Text(
                    request['time']?.toString() ?? '',
                    style: const TextStyle(color: greyText, fontSize: 11),
                  ),
                  if (request['status'] == 'accepted')
                    IconButton(
                      tooltip: 'Open Chat',
                      icon: const Icon(Icons.chat_bubble_outline, color: blue),
                      onPressed: () => _openConversationForRequest(request),
                    ),
                  if (request['status'] == 'pending')
                    IconButton(
                      tooltip: 'Cancel request',
                      onPressed: () => _cancelRequest(request),
                      icon: const Icon(Icons.cancel_outlined, color: red),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _conversationsPage() {
    final acceptedRequests =
        requests.where((r) => r['status'] == 'accepted').toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Conversations',
          style: TextStyle(
            color: darkBlue,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        if (acceptedRequests.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 48, horizontal: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 56, color: greyText),
                  SizedBox(height: 16),
                  Text(
                    'No active conversations',
                    style: TextStyle(
                      color: darkBlue,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'When a Liquidity Officer accepts your request, your chat will appear here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: greyText, fontSize: 13),
                  ),
                ],
              ),
            ),
          )
        else
          ...acceptedRequests.map(
            (request) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => _openConversationForRequest(request),
                borderRadius: BorderRadius.circular(18),
                child: _whiteCard(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      _Avatar(
                        letter:
                            (request['loName']?.toString().isNotEmpty ?? false)
                                ? request['loName']
                                    .toString()
                                    .substring(0, 1)
                                    .toUpperCase()
                                : 'L',
                        size: 42,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              request['loName']?.toString() ??
                                  'Liquidity Officer',
                              style: const TextStyle(
                                color: darkBlue,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${request['type'] ?? 'Request'} • ${request['amount'] ?? ''}',
                              style: const TextStyle(
                                color: greyText,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Open Chat',
                        icon: const Icon(Icons.chat, color: blue),
                        onPressed: () => _openConversationForRequest(request),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _morePage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'More',
          style: TextStyle(
            color: darkBlue,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        ListTile(
          leading: const CircleAvatar(
            backgroundColor: Color(0xFFE7F5FF),
            child: Icon(Icons.person, color: blue),
          ),
          title: const Text('Profile Details'),
          subtitle: Text(profile['username'] ?? 'Altrafloat User'),
          onTap: _openProfilePage,
        ),
        ListTile(
          leading: const CircleAvatar(
            backgroundColor: Color(0xFFE7F5FF),
            child: Icon(Icons.settings, color: blue),
          ),
          title: const Text('Settings'),
          subtitle: const Text('Notifications and preferences'),
          onTap: _openSettingsPage,
        ),
        ListTile(
          leading: const CircleAvatar(
            backgroundColor: Color(0xFFFFF0F0),
            child: Icon(Icons.logout, color: red),
          ),
          title: const Text('Logout'),
          onTap: _confirmLogout,
        ),
      ],
    );
  }

  Widget _agentHome() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(15, 5, 15, 20),
      child: Column(
        children: [
          _agentProfileCard(),
          if (_dashboardDataError != null) ...[
            const SizedBox(height: 8),
            Text(
              _dashboardDataError!,
              style: const TextStyle(color: red, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          _availableOfficerSummary(),
          const SizedBox(height: 12),
          _newRequestButton(),
          const SizedBox(height: 12),
          _quickActions(),
          const SizedBox(height: 18),
          _sectionHeader('Available LOs', 'View All'),
          const SizedBox(height: 8),
          if (availableOfficers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'No Liquidity Officers are currently available.',
                style: TextStyle(color: greyText, fontSize: 13),
              ),
            )
          else
            ...availableOfficers.map(
              (officer) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _officerCard(officer),
              ),
            ),
          const SizedBox(height: 5),
          _requestOverview(),
        ],
      ),
    );
  }

  Widget _agentProfileCard() {
    final username = profile['username'] ?? 'Altrafloat User';
    final id = profile['id'] ?? '';
    final category = profile['category'] ?? 'Main Agent';
    final firstLetter = username.isNotEmpty ? username[0].toUpperCase() : 'A';

    return _whiteCard(
      child: Row(
        children: [
          _Avatar(letter: firstLetter, size: 62),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Good morning,',
                  style: TextStyle(color: darkText, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  username,
                  style: const TextStyle(
                    color: darkBlue,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Agent ID: $id',
                  style: const TextStyle(color: greyText, fontSize: 12),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(
                      Icons.workspace_premium,
                      color: darkBlue,
                      size: 16,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      category,
                      style: const TextStyle(color: darkBlue, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            decoration: BoxDecoration(
              color: red,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text(
              'AGENT',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _availableOfficerSummary() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        color: const Color(0xFFDDF2FF),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.groups, color: blue, size: 28),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Available Liquidity Officers',
                  style: TextStyle(
                    color: darkBlue,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '${availableOfficers.length}',
                      style: TextStyle(
                        color: darkBlue,
                        fontSize: 25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(width: 8),
                    Icon(
                      Icons.circle,
                      color: availableOfficers.isEmpty ? greyText : green,
                      size: 9,
                    ),
                    SizedBox(width: 4),
                    Text(
                      availableOfficers.isEmpty ? 'None online' : 'Online now',
                      style: TextStyle(
                        color: availableOfficers.isEmpty ? greyText : green,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: darkBlue),
        ],
      ),
    );
  }

  Widget _newRequestButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: availableOfficers.isEmpty ? null : _openNewRequestDialog,
        style: ElevatedButton.styleFrom(
          backgroundColor: red,
          foregroundColor: Colors.white,
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.send),
            SizedBox(width: 10),
            Text(
              'New Request',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            Spacer(),
            Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  Widget _quickActions() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: _openChatPage,
            child: _quickAction(Icons.chat_bubble, 'Chat'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() {
                selectedIndex = 1;
              });
            },
            child: _quickAction(Icons.access_time, 'History'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: _openProfilePage,
            child: _quickAction(Icons.person, 'Profile'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: _openSettingsPage,
            child: _quickAction(Icons.settings, 'Settings'),
          ),
        ),
      ],
    );
  }

  Widget _quickAction(IconData icon, String title) {
    return Container(
      height: 82,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFD9EAF5)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: blue, size: 27),
          const SizedBox(height: 6),
          Text(
            title,
            style: const TextStyle(
              color: darkBlue,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, String action) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: darkBlue,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        const Spacer(),
        Text(
          action,
          style: const TextStyle(
            color: blue,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Icon(Icons.chevron_right, color: blue, size: 17),
      ],
    );
  }

  Widget _officerCard(Map<String, dynamic> officer) {
    final name = officer['name']?.toString() ?? '';
    final id = officer['id']?.toString() ?? '';
    final initial = name.isEmpty ? 'L' : name[0].toUpperCase();

    return _whiteCard(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      child: Row(
        children: [
          _Avatar(letter: initial, size: 48),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: darkBlue,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: blue,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Text(
                        'L.O.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    const Icon(Icons.circle, color: green, size: 8),
                    const SizedBox(width: 5),
                    Text(
                      id,
                      style: const TextStyle(color: greyText, fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            height: 38,
            child: ElevatedButton(
              onPressed: () => _openNewRequestDialog(selectedOfficer: officer),
              style: ElevatedButton.styleFrom(
                backgroundColor: blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: const Text(
                'Request',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const Icon(Icons.chevron_right, color: blue, size: 20),
        ],
      ),
    );
  }

  Widget _requestOverview() {
    return _whiteCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                'Request Overview',
                style: TextStyle(
                  color: darkBlue,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              const Text(
                'View Details',
                style: TextStyle(
                  color: blue,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Icon(Icons.chevron_right, color: blue, size: 16),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              _stat(
                Icons.access_time,
                '$_requestCountPending',
                'Pending',
                const Color(0xFFE79A23),
              ),
              _verticalDivider(),
              _stat(
                Icons.check_circle_outline,
                '$_requestCountAccepted',
                'Accepted',
                green,
              ),
              _verticalDivider(),
              _stat(
                Icons.cancel_outlined,
                '$_requestCountDeclined',
                'Declined',
                red,
              ),
              _verticalDivider(),
              _stat(
                Icons.block_outlined,
                '$_requestCountCancelled',
                'Cancelled',
                greyText,
              ),
            ],
          ),
        ],
      ),
    );
  }

  int get _requestCountPending => _requestCount('pending');
  int get _requestCountAccepted => _requestCount('accepted');
  int get _requestCountDeclined => _requestCount('declined');
  int get _requestCountCancelled => _requestCount('cancelled');

  Widget _stat(IconData icon, String value, String title, Color color) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _verticalDivider() {
    return Container(height: 52, width: 1, color: const Color(0xFFD7E8F3));
  }

  Widget _whiteCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(12),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7DB5D8).withValues(alpha: .10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _agentNavigation() {
    return NavigationBar(
      height: 70,
      backgroundColor: Colors.white,
      indicatorColor: Colors.transparent,
      selectedIndex: selectedIndex,
      onDestinationSelected: (index) {
        setState(() {
          selectedIndex = index;
        });
      },
      destinations: [
        _navItem(Icons.home, 'Home'),
        _navItem(Icons.description, 'Requests'),
        _navItem(Icons.chat_bubble, 'Chat'),
        _navItem(Icons.more_horiz, 'More'),
      ],
    );
  }

  NavigationDestination _navItem(IconData icon, String label) {
    return NavigationDestination(
      icon: Icon(icon, color: const Color(0xFF70A1C5)),
      selectedIcon: Icon(icon, color: red),
      label: label,
    );
  }
}

class _NewRequestDialog extends StatefulWidget {
  final List<Map<String, dynamic>> availableOfficers;
  final Map<String, dynamic>? selectedOfficer;
  final VoidCallback onCancel;
  final ValueChanged<Map<String, String>> onSend;

  const _NewRequestDialog({
    required this.availableOfficers,
    required this.selectedOfficer,
    required this.onCancel,
    required this.onSend,
  });

  @override
  State<_NewRequestDialog> createState() => _NewRequestDialogState();
}

class _NewRequestDialogState extends State<_NewRequestDialog> {
  late final TextEditingController _typeController;
  late final TextEditingController _amountController;
  late final TextEditingController _messageController;
  late String _selectedOfficerUid;

  @override
  void initState() {
    super.initState();
    _typeController = TextEditingController(text: 'Cash Request');
    _amountController = TextEditingController();
    _messageController = TextEditingController();
    _selectedOfficerUid =
        widget.selectedOfficer?['uid']?.toString() ??
        widget.availableOfficers.first['uid'].toString();
  }

  @override
  void dispose() {
    _typeController.dispose();
    _amountController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('New Request'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _typeController.text,
              decoration: const InputDecoration(labelText: 'Request Type'),
              items: const [
                DropdownMenuItem(
                  value: 'Cash Request',
                  child: Text('Cash Request'),
                ),
                DropdownMenuItem(
                  value: 'Airtime Request',
                  child: Text('Airtime Request'),
                ),
                DropdownMenuItem(
                  value: 'Loan Request',
                  child: Text('Loan Request'),
                ),
              ],
              onChanged:
                  (value) =>
                      _typeController.text = value ?? _typeController.text,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedOfficerUid,
              decoration: const InputDecoration(labelText: 'Liquidity Officer'),
              items:
                  widget.availableOfficers
                      .map(
                        (officer) => DropdownMenuItem(
                          value: officer['uid'].toString(),
                          child: Text('${officer['name']} (${officer['id']})'),
                        ),
                      )
                      .toList(),
              onChanged: (value) {
                if (value != null) _selectedOfficerUid = value;
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Amount',
                hintText: 'Enter amount',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _messageController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Message',
                hintText: 'Tell the L.O. what you need',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            widget.onSend({
              'type': _typeController.text,
              'amount': _amountController.text.trim(),
              'message': _messageController.text.trim(),
              'loUid': _selectedOfficerUid,
            });
          },
          child: const Text('Send'),
        ),
      ],
    );
  }
}

// ============================================================
// LIQUIDITY OFFICER DASHBOARD
// ============================================================

class LiquidityOfficerDashboard extends StatefulWidget {
  const LiquidityOfficerDashboard({super.key});

  @override
  State<LiquidityOfficerDashboard> createState() =>
      _LiquidityOfficerDashboardState();
}

class _LiquidityOfficerDashboardState extends State<LiquidityOfficerDashboard> {
  int selectedIndex = 0;
  bool online = false;
  bool _checkingAuthorization = true;
  bool _isAuthorized = false;
  bool _authorizationVerificationFailed = false;
  String? _dashboardDataError;
  Map<String, String> profile = {
    'username': 'Liquidity Officer',
    'email': '',
    'role': 'Liquidity Officer',
    'id': '',
    'category': 'Liquidity Officer',
  };

  List<Map<String, dynamic>> requests = [];
  StreamSubscription<List<Map<String, dynamic>>>? _requestsSubscription;
  StreamSubscription<bool>? _availabilitySubscription;

  @override
  void initState() {
    super.initState();
    _loadDashboardState();
  }

  Future<void> _loadDashboardState() async {
    try {
      final savedProfile = await AppStorage.loadAuthorizedProfile(
        role: 'Liquidity Officer',
      );
      if (savedProfile == null) {
        if (Firebase.apps.isNotEmpty &&
            FirebaseAuth.instance.currentUser != null) {
          await FcmService.instance.signOut();
        }
        if (!mounted) return;
        setState(() => _checkingAuthorization = false);
        return;
      }

      await AppStorage.ensureLOAvailability(savedProfile);
      if (!mounted) return;
      setState(() {
        profile = savedProfile;
        _isAuthorized = true;
        _checkingAuthorization = false;
      });

      await _requestsSubscription?.cancel();
      await _availabilitySubscription?.cancel();
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      _requestsSubscription = AppStorage.watchLORequests(uid).listen(
        (savedRequests) {
          if (!mounted) return;
          setState(() {
            requests = savedRequests;
            _dashboardDataError = null;
          });
        },
        onError: (Object error, StackTrace stackTrace) {
          _showDashboardDataError('Could not load your incoming requests.');
        },
      );
      _availabilitySubscription = AppStorage.watchLOAvailability(uid).listen(
        (available) {
          if (!mounted) return;
          setState(() {
            online = available;
            _dashboardDataError = null;
          });
        },
        onError: (Object error, StackTrace stackTrace) {
          _showDashboardDataError('Could not load your availability status.');
        },
      );
    } on FirebaseException {
      if (Firebase.apps.isNotEmpty &&
          FirebaseAuth.instance.currentUser != null) {
        await FcmService.instance.signOut();
      }
      if (!mounted) return;
      setState(() {
        _checkingAuthorization = false;
        _authorizationVerificationFailed = true;
      });
    }
  }

  void _showDashboardDataError(String message) {
    if (!mounted) return;
    setState(() => _dashboardDataError = message);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _requestsSubscription?.cancel();
    _availabilitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _confirmLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to log out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );

    if (shouldLogout != true) return;

    await FcmService.instance.signOut();
    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  Future<void> _acceptRequest(Map<String, dynamic> request) async {
    final requestId = request['_documentId']?.toString();
    try {
      await AppStorage.updateRequestStatus(
        documentId: requestId ?? '',
        status: 'accepted',
      );
      if (requestId != null) {
        try {
          await cs.ChatService.instance.ensureConversation(requestId);
        } on cs.ChatServiceException catch (e) {
          if (kDebugMode) {
            debugPrint(
              'ensureConversation failed after accept: ${e.failure.name}',
            );
          }
          final isRecoverable =
              e.failure == cs.ChatServiceFailure.unavailable ||
              e.failure == cs.ChatServiceFailure.unknown;
          if (!isRecoverable && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Request accepted. Chat setup will complete when you open the conversation.',
                ),
              ),
            );
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('ensureConversation unexpected error: $e');
          }
        }
      }
    } on FirebaseException {
      _showDashboardDataError('Could not accept this request.');
    }
  }

  Future<void> _openConversationForRequest(Map<String, dynamic> request) async {
    final status = request['status']?.toString();
    if (status != 'accepted') {
      _showDashboardDataError('Chat is only available for accepted requests.');
      return;
    }

    final requestId = request['_documentId']?.toString();
    final agentUid = request['agentUid']?.toString();
    final loUid = request['loUid']?.toString();
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    if (requestId == null ||
        agentUid == null ||
        loUid == null ||
        currentUid == null) {
      _showDashboardDataError('Unable to open chat: missing credentials.');
      return;
    }

    if (currentUid != loUid) {
      _showDashboardDataError('You are not authorized for this conversation.');
      return;
    }

    try {
      await cs.ChatService.instance.ensureConversation(requestId);
    } on cs.ChatServiceException catch (e) {
      _showDashboardDataError(
        'Could not start conversation (${e.failure.name}).',
      );
      return;
    } catch (_) {
      _showDashboardDataError('Could not start conversation.');
      return;
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => ChatPage(
              currentUser: profile['username'] ?? 'Liquidity Officer',
              currentRole: 'Liquidity Officer',
              otherUser: request['agentName']?.toString() ?? 'Agent',
              otherRole: 'Agent',
              chatId: requestId,
              currentUid: currentUid,
              counterpartUid: agentUid,
            ),
      ),
    );
  }

  Future<void> _declineRequest(Map<String, dynamic> request) async {
    final reasonController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('Decline Request'),
          content: TextField(
            controller: reasonController,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Enter reason for declining',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed:
                  () => Navigator.pop(context, reasonController.text.trim()),
              style: ElevatedButton.styleFrom(
                backgroundColor: red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Decline'),
            ),
          ],
        );
      },
    );

    if (result == null) return;
    if (result.trim().isEmpty) {
      _showDashboardDataError('Enter a reason before declining the request.');
      return;
    }

    try {
      await AppStorage.updateRequestStatus(
        documentId: request['_documentId'].toString(),
        status: 'declined',
        declineReason: result.trim(),
      );
    } on FirebaseException {
      _showDashboardDataError('Could not decline this request.');
    }
  }

  Future<void> _setAvailability(bool available) async {
    try {
      await AppStorage.setLOAvailability(
        profile: profile,
        available: available,
      );
    } on FirebaseException {
      _showDashboardDataError('Could not update your availability.');
    }
  }

  Future<void> _openProfilePage() async {
    final saved = await AppStorage.loadProfile();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _ProfileDetailsPage(profile: saved)),
    );
    _loadDashboardState();
  }

  void _openNotificationsPage() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NotificationListPage()),
    );
  }

  Future<void> _openSettingsPage() async {
    final saved = await AppStorage.loadProfile();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _SettingsPage(profile: saved)),
    );
    _loadDashboardState();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthorized) {
      return _dashboardAccessPage(
        context,
        role: 'Liquidity Officer',
        isVerifying: _checkingAuthorization,
        verificationFailed: _authorizationVerificationFailed,
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF2F9FE),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF2F9FE),
        elevation: 0,
        leading: IconButton(
          onPressed: () {},
          icon: const Icon(Icons.menu, color: darkBlue, size: 28),
        ),
        titleSpacing: 0,
        title: const AltrafloatBrand(),
        actions: [
          IconButton(
            onPressed: _openNotificationsPage,
            icon: const Icon(
              Icons.notifications_none,
              color: darkBlue,
              size: 28,
            ),
          ),
          IconButton(
            onPressed: _confirmLogout,
            icon: const Icon(Icons.logout, color: darkBlue, size: 26),
            tooltip: 'Logout',
          ),
          IconButton(
            onPressed: _openProfilePage,
            icon: const CircleAvatar(
              radius: 18,
              backgroundColor: Color(0xFFDDF0FF),
              child: Icon(Icons.person, color: darkBlue),
            ),
          ),
          const SizedBox(width: 5),
        ],
      ),
      body: SafeArea(child: _loBody()),
      bottomNavigationBar: _loNavigation(),
    );
  }

  Widget _loBody() {
    if (selectedIndex == 1) return _requestsPage();
    if (selectedIndex == 2) return _historyPage();
    if (selectedIndex == 3) return _conversationsPage();
    if (selectedIndex == 4) return _morePage();
    return _loHome();
  }

  Widget _requestsPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Incoming Requests',
          style: TextStyle(
            color: darkBlue,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        if (!requests.any((request) => request['status'] == 'pending'))
          const Text('No incoming requests.')
        else
          ...requests
              .where((request) => request['status'] == 'pending')
              .map(
                (request) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _incomingRequest(request),
                ),
              ),
      ],
    );
  }

  Widget _historyPage() {
    final history =
        requests
            .where((request) => (request['status'] ?? 'pending') != 'pending')
            .toList();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'History',
          style: TextStyle(
            color: darkBlue,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        if (history.isEmpty)
          const Text('No request history yet.')
        else
          ...history.map(
            (request) => _whiteCard(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _Avatar(
                    letter:
                        (request['letter'] ?? 'A')
                            .toString()
                            .substring(0, 1)
                            .toUpperCase(),
                    size: 42,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          request['type']?.toString() ?? 'Request',
                          style: const TextStyle(
                            color: darkBlue,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${request['status'] ?? 'updated'} • ${request['amount'] ?? ''}',
                          style: const TextStyle(color: greyText, fontSize: 12),
                        ),
                        if (request['declineReason'] is String &&
                            (request['declineReason'] as String).isNotEmpty)
                          Text(
                            'Reason: ${request['declineReason']}',
                            style: const TextStyle(
                              color: greyText,
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    request['time']?.toString() ?? '',
                    style: const TextStyle(color: greyText, fontSize: 11),
                  ),
                  if (request['status'] == 'accepted')
                    IconButton(
                      tooltip: 'Open Chat',
                      icon: const Icon(Icons.chat_bubble_outline, color: blue),
                      onPressed: () => _openConversationForRequest(request),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _conversationsPage() {
    final acceptedRequests =
        requests.where((r) => r['status'] == 'accepted').toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Conversations',
          style: TextStyle(
            color: darkBlue,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        if (acceptedRequests.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 48, horizontal: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 56, color: greyText),
                  SizedBox(height: 16),
                  Text(
                    'No active conversations',
                    style: TextStyle(
                      color: darkBlue,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'When you accept an agent request, your conversation will appear here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: greyText, fontSize: 13),
                  ),
                ],
              ),
            ),
          )
        else
          ...acceptedRequests.map(
            (request) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => _openConversationForRequest(request),
                borderRadius: BorderRadius.circular(18),
                child: _whiteCard(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      _Avatar(
                        letter:
                            (request['agentName']?.toString().isNotEmpty ??
                                    false)
                                ? request['agentName']
                                    .toString()
                                    .substring(0, 1)
                                    .toUpperCase()
                                : 'A',
                        size: 42,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              request['agentName']?.toString() ?? 'Agent',
                              style: const TextStyle(
                                color: darkBlue,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${request['type'] ?? 'Request'} • ${request['amount'] ?? ''}',
                              style: const TextStyle(
                                color: greyText,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Open Chat',
                        icon: const Icon(Icons.chat, color: blue),
                        onPressed: () => _openConversationForRequest(request),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _morePage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'More',
          style: TextStyle(
            color: darkBlue,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 16),
        ListTile(
          leading: const CircleAvatar(
            backgroundColor: Color(0xFFE7F5FF),
            child: Icon(Icons.person, color: blue),
          ),
          title: const Text('Profile Details'),
          subtitle: Text(profile['username'] ?? 'Liquidity Officer'),
          onTap: _openProfilePage,
        ),
        ListTile(
          leading: const CircleAvatar(
            backgroundColor: Color(0xFFE7F5FF),
            child: Icon(Icons.settings, color: blue),
          ),
          title: const Text('L.O. Settings'),
          subtitle: const Text('Security and notifications'),
          onTap: _openSettingsPage,
        ),
        ListTile(
          leading: const CircleAvatar(
            backgroundColor: Color(0xFFFFF0F0),
            child: Icon(Icons.logout, color: red),
          ),
          title: const Text('Logout'),
          onTap: _confirmLogout,
        ),
      ],
    );
  }

  Widget _loHome() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(15, 5, 15, 20),
      child: Column(
        children: [
          _loProfileCard(),
          if (_dashboardDataError != null) ...[
            const SizedBox(height: 8),
            Text(
              _dashboardDataError!,
              style: const TextStyle(color: red, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          _loSummaryCards(),
          const SizedBox(height: 17),
          Row(
            children: [
              const Text(
                'Incoming Agent Requests',
                style: TextStyle(
                  color: darkBlue,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 7),
              Container(
                width: 23,
                height: 23,
                decoration: const BoxDecoration(
                  color: red,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${requests.where((request) => (request['status'] ?? 'pending') == 'pending').length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => selectedIndex = 1),
                child: const Text(
                  'View All',
                  style: TextStyle(
                    color: blue,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          if (!requests.any((request) => request['status'] == 'pending'))
            const Text(
              'No incoming requests.',
              style: TextStyle(color: greyText, fontSize: 13),
            )
          else
            ...requests
                .where((request) => request['status'] == 'pending')
                .map(
                  (request) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _incomingRequest(request),
                  ),
                ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
            decoration: BoxDecoration(
              color: const Color(0xFFDFF4FF),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Row(
              children: [
                const Icon(Icons.groups, color: blue, size: 25),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    online
                        ? 'You are online and available\nto respond to agent requests.'
                        : 'You are currently offline.\nToggle on to receive requests.',
                    style: const TextStyle(
                      color: darkBlue,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, color: blue),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _loProfileCard() {
    final username = profile['username'] ?? 'Liquidity Officer';
    final id = profile['id'] ?? '';
    final firstLetter = username.isNotEmpty ? username[0].toUpperCase() : 'L';

    return _whiteCard(
      child: Row(
        children: [
          _Avatar(letter: firstLetter, size: 62),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Good morning,',
                  style: TextStyle(color: darkText, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  username,
                  style: const TextStyle(
                    color: darkBlue,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'LO ID: $id',
                  style: const TextStyle(color: greyText, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.circle,
                      color: online ? green : greyText,
                      size: 10,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      online ? 'Status: Active' : 'Status: Offline',
                      style: TextStyle(
                        color: online ? green : greyText,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: 90,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: blue,
              borderRadius: BorderRadius.circular(17),
            ),
            child: const Text(
              'LIQUIDITY\nOFFICER',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.bold,
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _loSummaryCards() {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 94,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEEF0),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: red,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.inbox, color: Colors.white, size: 23),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Incoming Requests',
                        style: TextStyle(
                          color: darkBlue,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${requests.where((request) => (request['status'] ?? 'pending') == 'pending').length}',
                        style: const TextStyle(
                          color: darkBlue,
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: darkBlue),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Container(
            height: 94,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: const Color(0xFFE7F5FF),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.access_time, color: blue, size: 27),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Online',
                        style: TextStyle(
                          color: darkBlue,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        children: [
                          Switch(
                            value: online,
                            activeColor: green,
                            onChanged: _setAvailability,
                          ),
                          const Flexible(
                            child: Text(
                              'Available',
                              style: TextStyle(color: darkBlue, fontSize: 10),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _incomingRequest(Map<String, dynamic> request) {
    return _whiteCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Row(
        children: [
          _Avatar(
            letter:
                (request['letter'] ?? 'A')
                    .toString()
                    .substring(0, 1)
                    .toUpperCase(),
            size: 44,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: request['name']?.toString() ?? 'Agent',
                        style: const TextStyle(
                          color: darkBlue,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const TextSpan(
                        text: ' (Agent)',
                        style: TextStyle(color: greyText, fontSize: 10),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${request['id'] ?? ''}  •  ${request['type'] ?? 'Request'}',
                  style: const TextStyle(color: greyText, fontSize: 9),
                ),
                if ((request['message'] ?? '').toString().isNotEmpty)
                  Text(
                    request['message'].toString(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: greyText, fontSize: 10),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                request['amount']?.toString() ?? '',
                style: const TextStyle(
                  color: darkBlue,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                request['time']?.toString() ?? '',
                style: const TextStyle(color: greyText, fontSize: 9),
              ),
            ],
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 54,
            height: 31,
            child: ElevatedButton(
              onPressed: () => _acceptRequest(request),
              style: ElevatedButton.styleFrom(
                backgroundColor: blue,
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
              child: const Text(
                'Accept',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 54,
            height: 31,
            child: ElevatedButton(
              onPressed: () => _declineRequest(request),
              style: ElevatedButton.styleFrom(
                backgroundColor: red,
                foregroundColor: Colors.white,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
              child: const Text(
                'Decline',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _whiteCard({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(12),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7DB5D8).withValues(alpha: .10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _loNavigation() {
    return NavigationBar(
      height: 70,
      backgroundColor: Colors.white,
      indicatorColor: Colors.transparent,
      selectedIndex: selectedIndex,
      onDestinationSelected: (index) {
        if (index == 4) {
          _showMoreMenu();
        } else {
          setState(() {
            selectedIndex = index;
          });
        }
      },
      destinations: [
        NavigationDestination(
          icon: const Icon(Icons.home, color: Color(0xFF70A1C5)),
          selectedIcon: const Icon(Icons.home, color: red),
          label: 'Home',
        ),
        NavigationDestination(
          icon: const Icon(Icons.description, color: Color(0xFF70A1C5)),
          selectedIcon: const Icon(Icons.description, color: red),
          label: 'Requests',
        ),
        NavigationDestination(
          icon: const Icon(Icons.access_time, color: Color(0xFF70A1C5)),
          selectedIcon: const Icon(Icons.access_time, color: red),
          label: 'History',
        ),
        NavigationDestination(
          icon: const Icon(Icons.chat_bubble, color: Color(0xFF70A1C5)),
          selectedIcon: const Icon(Icons.chat_bubble, color: red),
          label: 'Chat',
        ),
        NavigationDestination(
          icon: const Icon(Icons.more_horiz, color: Color(0xFF70A1C5)),
          selectedIcon: const Icon(Icons.more_horiz, color: red),
          label: 'More',
        ),
      ],
    );
  }

  void _showMoreMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 45,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE7F5FF),
                    child: Icon(Icons.settings, color: blue),
                  ),
                  title: const Text(
                    'L.O. Settings',
                    style: TextStyle(
                      color: darkBlue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(context);
                    _openSettingsPage();
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE7F5FF),
                    child: Icon(Icons.person, color: blue),
                  ),
                  title: const Text(
                    'Profile Details',
                    style: TextStyle(
                      color: darkBlue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(context);
                    _openProfilePage();
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFFFF0F0),
                    child: Icon(Icons.logout, color: red),
                  ),
                  title: const Text(
                    'Logout',
                    style: TextStyle(
                      color: darkBlue,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(context);
                    _confirmLogout();
                  },
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ============================================================
// AVATAR
// ============================================================

class _Avatar extends StatelessWidget {
  final String letter;
  final double size;

  const _Avatar({required this.letter, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE3F5FF), Color(0xFFB8E2FF)],
        ),
        border: Border.all(color: const Color(0xFF91D0F5), width: 1.2),
      ),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            color: darkBlue,
            fontSize: size * .38,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
// ============================================================
// PROFILE DETAILS PAGE
// ============================================================

class _ProfileDetailsPage extends StatelessWidget {
  final Map<String, String> profile;

  const _ProfileDetailsPage({required this.profile});

  @override
  Widget build(BuildContext context) {
    final username = profile['username'] ?? 'Altrafloat User';
    final email = profile['email'] ?? 'No email set';
    final id = profile['id'] ?? '';
    final role = profile['role'] ?? 'Agent';
    final category = profile['category'] ?? 'Main Agent';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile Details'),
        backgroundColor: const Color(0xFFF2F9FE),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 10),
            CircleAvatar(
              radius: 42,
              backgroundColor: const Color(0xFFE7F5FF),
              child: Text(
                username.isNotEmpty ? username[0].toUpperCase() : 'A',
                style: const TextStyle(
                  color: darkBlue,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 18),
            _ProfileField(label: 'Username', value: username),
            _ProfileField(label: 'Email', value: email),
            _ProfileField(label: 'Role', value: role),
            _ProfileField(label: 'ID', value: id),
            _ProfileField(label: 'Category', value: category),
          ],
        ),
      ),
    );
  }
}

class _ProfileField extends StatelessWidget {
  final String label;
  final String value;

  const _ProfileField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD9EAF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: greyText,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: darkBlue,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SETTINGS PAGE
// ============================================================

class _SettingsPage extends StatefulWidget {
  final Map<String, String> profile;

  const _SettingsPage({required this.profile});

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  bool notificationsEnabled = true;
  bool soundEnabled = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: const Color(0xFFF2F9FE),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          SwitchListTile(
            value: notificationsEnabled,
            onChanged: (value) => setState(() => notificationsEnabled = value),
            title: const Text('Push notifications'),
            subtitle: const Text('Receive request and message alerts'),
            activeColor: blue,
          ),
          SwitchListTile(
            value: soundEnabled,
            onChanged: (value) => setState(() => soundEnabled = value),
            title: const Text('Sound alerts'),
            subtitle: const Text('Play sound for new notifications'),
            activeColor: blue,
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.lock_outline, color: blue),
            title: const Text('Change password'),
            onTap: () async {
              final currentUser = FirebaseAuth.instance.currentUser;
              if (currentUser == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'You must be signed in to reset your password.',
                    ),
                  ),
                );
                return;
              }

              final email = currentUser.email;
              if (email == null || email.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'There is no email address associated with your account.',
                    ),
                  ),
                );
                return;
              }

              try {
                await FirebaseAuth.instance.sendPasswordResetEmail(
                  email: email,
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Password reset email sent to $email. '
                      'Please check your inbox and spam folder.',
                    ),
                  ),
                );
              } on FirebaseAuthException catch (e) {
                if (!context.mounted) return;
                final message = switch (e.code) {
                  'invalid-email' =>
                    'The email address associated with your account is invalid.',
                  'user-not-found' =>
                    'No account was found for this email address.',
                  'too-many-requests' =>
                    'Too many reset attempts. Please wait and try again.',
                  'network-request-failed' =>
                    'Unable to connect. Check your internet connection and try again.',
                  _ =>
                    'Unable to send a password reset email. Please try again.',
                };
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(message)));
              } catch (_) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Unable to send a password reset email. Please try again.',
                    ),
                  ),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.shield_outlined, color: blue),
            title: const Text('Privacy & security'),
            onTap: () {},
          ),
          const SizedBox(height: 30),
          ElevatedButton.icon(
            onPressed: () async {
              await AppStorage.saveProfile(
                username: widget.profile['username'] ?? 'Altrafloat User',
                email: widget.profile['email'] ?? '',
                role: widget.profile['role'] ?? 'Agent',
                id: widget.profile['id'] ?? '',
                category: widget.profile['category'] ?? 'Main Agent',
              );
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Settings saved successfully.')),
              );
            },
            icon: const Icon(Icons.save),
            label: const Text('Save settings'),
            style: ElevatedButton.styleFrom(
              backgroundColor: blue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}
// ============================================================
// CHAT PAGE
// ============================================================

class ChatPage extends StatefulWidget {
  final String currentUser;
  final String currentRole;
  final String otherUser;
  final String otherRole;
  final String chatId;
  final String? currentUid;
  final String? counterpartUid;
  final cs.ChatService? chatService;

  const ChatPage({
    super.key,
    required this.currentUser,
    required this.currentRole,
    required this.otherUser,
    required this.otherRole,
    required this.chatId,
    this.currentUid,
    this.counterpartUid,
    this.chatService,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isLive = false;
  StreamSubscription<cs.ChatPage<cs.ChatMessage, cs.ChatMessageCursor>>?
      _subscription;

  List<cs.ChatMessage> _liveMessages = [];
  cs.ChatMessageCursor? _olderCursor;
  bool _hasMore = false;
  bool _isLoadingOlder = false;
  bool _hasLoadedOlderMessages = false;

  final Set<String> _markedDelivered = {};
  final Set<String> _markedRead = {};

  List<Map<String, String>> _legacyMessages = [];

  cs.ChatService get _effectiveChatService =>
      widget.chatService ?? cs.ChatService.instance;

  @override
  void initState() {
    super.initState();

    final hasCustomService = widget.chatService != null;
    final isLiveChatId =
        widget.chatId != 'agent_lo' && widget.chatId != 'test_chat';
    final hasFirebase = Firebase.apps.isNotEmpty;

    if (hasCustomService || (hasFirebase && isLiveChatId)) {
      _isLive = true;
      _initLiveChat();
    } else {
      _isLive = false;
      _loadLegacyMessages();
    }
  }

  void _initLiveChat() {
    _scrollController.addListener(_onScroll);

    try {
      _subscription = _effectiveChatService
          .watchLatestMessages(widget.chatId)
          .listen(
        (page) {
          if (!mounted) return;

          setState(() {
            final merged = <String, cs.ChatMessage>{
              for (final message in _liveMessages)
                message.id: message,
              for (final message in page.items)
                message.id: message,
            };

            _liveMessages = merged.values.toList()
              ..sort((a, b) {
                final aTime = a.createdAt;
                final bTime = b.createdAt;

                if (aTime == null && bTime == null) {
                  return a.id.compareTo(b.id);
                }
                if (aTime == null) return -1;
                if (bTime == null) return 1;

                final byTime = aTime.compareTo(bTime);
                return byTime != 0
                    ? byTime
                    : a.id.compareTo(b.id);
              });

            if (!_hasLoadedOlderMessages) {
              _olderCursor = page.nextCursor;
              _hasMore = page.hasMore;
            }
          });

          _handleIncomingReceipts(page.items);
        },
        onError: (error) {
          if (kDebugMode) {
            debugPrint('Live chat stream error: $error');
          }
        },
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Could not initialize live chat: $e');
      }
    }
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 80) {
      _loadOlderMessages();
    }
  }

  Future<void> _loadOlderMessages() async {
    if (!_hasMore || _isLoadingOlder || _olderCursor == null) {
      return;
    }

    _isLoadingOlder = true;

    try {
      final olderPage =
          await _effectiveChatService.loadOlderMessages(
        widget.chatId,
        before: _olderCursor,
      );

      if (!mounted) return;

      setState(() {
        _hasLoadedOlderMessages = true;
        _olderCursor = olderPage.nextCursor;
        _hasMore = olderPage.hasMore;

        final existingIds =
            _liveMessages.map((message) => message.id).toSet();

        for (final item in olderPage.items) {
          if (!existingIds.contains(item.id)) {
            _liveMessages.add(item);
          }
        }

        _liveMessages.sort((a, b) {
          final aTime = a.createdAt;
          final bTime = b.createdAt;

          if (aTime == null && bTime == null) {
            return a.id.compareTo(b.id);
          }
          if (aTime == null) return -1;
          if (bTime == null) return 1;

          final byTime = aTime.compareTo(bTime);
          return byTime != 0
              ? byTime
              : a.id.compareTo(b.id);
        });
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error loading older messages: $e');
      }
    } finally {
      _isLoadingOlder = false;
    }
  }

  void _handleIncomingReceipts(List<cs.ChatMessage> items) {
    final myUid = widget.currentUid ??
        (Firebase.apps.isNotEmpty
            ? FirebaseAuth.instance.currentUser?.uid
            : null);

    if (myUid == null) return;

    for (final message in items) {
      if (message.senderUid != myUid) {
        if (message.deliveredAt == null &&
            !_markedDelivered.contains(message.id)) {
          _markedDelivered.add(message.id);

          _effectiveChatService
              .markDelivered(
                requestId: widget.chatId,
                messageId: message.id,
              )
              .catchError((_) {});
        }

        if (message.readAt == null &&
            !_markedRead.contains(message.id)) {
          _markedRead.add(message.id);

          _effectiveChatService
              .markRead(
                requestId: widget.chatId,
                messageId: message.id,
              )
              .catchError((_) {});
        }
      } else {
        if (message.deliveredAt != null) {
          _markedDelivered.add(message.id);
        }
        if (message.readAt != null) {
          _markedRead.add(message.id);
        }
      }
    }
  }

  Future<void> _loadLegacyMessages() async {
    final all = await AppStorage.loadChatMessages();

    final chatMessages = all
        .where(
          (message) =>
              (message['chatId'] ?? 'agent_lo') == widget.chatId,
        )
        .toList();

    var hasReadUpdates = false;

    for (final message in chatMessages) {
      if (_legacyMessageRole(message) !=
              _normalizeRole(widget.currentRole) &&
          message['read'] != 'true') {
        message['read'] = 'true';
        hasReadUpdates = true;
      }
    }

    if (hasReadUpdates) {
      await AppStorage.saveChatMessages(all);
    }

    if (!mounted) return;

    setState(() {
      _legacyMessages = chatMessages;
    });
  }

  String _normalizeRole(String role) {
    final normalized = role.toLowerCase();

    return normalized == 'lo' || normalized.contains('liquidity')
        ? 'Liquidity Officer'
        : 'Agent';
  }

  String _legacyMessageRole(Map<String, String> message) {
    final role = message['senderRole'];

    if (role != null && role.isNotEmpty) {
      return _normalizeRole(role);
    }

    return _normalizeRole(message['sender'] ?? 'Agent');
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();

    if (text.isEmpty) return;

    if (_isLive) {
      _messageController.clear();

      try {
        await _effectiveChatService.sendMessage(
          requestId: widget.chatId,
          text: text,
        );
      } catch (error) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not send message. Please try again.',
            ),
          ),
        );
      }
    } else {
      final message = {
        'sender': widget.currentUser,
        'senderRole': widget.currentRole,
        'text': text,
        'time': AppStorage._currentTime(),
        'chatId': widget.chatId,
        'read': 'false',
      };

      await AppStorage.appendChatMessage(message);
      _messageController.clear();
      await _loadLegacyMessages();
    }
  }

  Widget _buildStatusIcon(cs.ChatMessage message) {
    IconData iconData;
    Color iconColor;

    switch (message.status) {
      case cs.ChatMessageStatus.sending:
        iconData = Icons.access_time;
        iconColor = Colors.white70;
        break;
      case cs.ChatMessageStatus.sent:
        iconData = Icons.check;
        iconColor = Colors.white70;
        break;
      case cs.ChatMessageStatus.delivered:
        iconData = Icons.done_all;
        iconColor = Colors.white70;
        break;
      case cs.ChatMessageStatus.read:
        iconData = Icons.done_all;
        iconColor = const Color(0xFF4FC3F7);
        break;
    }

    final isRead =
        message.status == cs.ChatMessageStatus.read;

    return Icon(
      iconData,
      key: ValueKey('chat-read-${message.text}-$isRead'),
      size: 15,
      color: iconColor,
    );
  }

  String _formatMessageTime(DateTime? date) {
    if (date == null) return '';

    final local = date.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    final minute = local.minute.toString().padLeft(2, '0');

    return '$hour:$minute $suffix';
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _scrollController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.otherUser} (${widget.otherRole})'),
        backgroundColor: const Color(0xFFF2F9FE),
      ),
      body: Column(
        children: [
          Expanded(
            child: _isLive
                ? _buildLiveMessageList()
                : _buildLegacyMessageList(),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: 'Type message...',
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding:
                            const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 15,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton(
                    onPressed: _sendMessage,
                    backgroundColor: blue,
                    child: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveMessageList() {
    final myUid = widget.currentUid ??
        (Firebase.apps.isNotEmpty
            ? FirebaseAuth.instance.currentUser?.uid
            : null);

    final displayMessages = _liveMessages.reversed.toList();

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: displayMessages.length,
      itemBuilder: (context, index) {
        final message = displayMessages[index];
        final isMine =
            myUid != null && message.senderUid == myUid;
        final formattedTime =
            _formatMessageTime(message.createdAt);

        return Align(
          alignment:
              isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            key: ValueKey('chat-message-${message.id}'),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            constraints: const BoxConstraints(maxWidth: 280),
            decoration: BoxDecoration(
              color: isMine ? blue : Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.text,
                  style: TextStyle(
                    color: isMine ? Colors.white : darkBlue,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      formattedTime,
                      style: TextStyle(
                        color:
                            isMine ? Colors.white70 : greyText,
                        fontSize: 10,
                      ),
                    ),
                    if (isMine) ...[
                      const SizedBox(width: 4),
                      _buildStatusIcon(message),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLegacyMessageList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _legacyMessages.length,
      itemBuilder: (context, index) {
        final message = _legacyMessages[index];
        final senderRole = _legacyMessageRole(message);
        final isMine =
            senderRole == _normalizeRole(widget.currentRole);
        final isRead = message['read'] == 'true';

        return Align(
          alignment: senderRole == 'Agent'
              ? Alignment.centerLeft
              : Alignment.centerRight,
          child: Container(
            key: ValueKey('chat-message-${message['text']}'),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            constraints: const BoxConstraints(maxWidth: 280),
            decoration: BoxDecoration(
              color: isMine ? blue : Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message['text'] ?? '',
                  style: TextStyle(
                    color: isMine ? Colors.white : darkBlue,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      message['time'] ?? '',
                      style: TextStyle(
                        color:
                            isMine ? Colors.white70 : greyText,
                        fontSize: 10,
                      ),
                    ),
                    if (isMine) ...[
                      const SizedBox(width: 4),
                      Icon(
                        isRead ? Icons.done_all : Icons.check,
                        key: ValueKey(
                          'chat-read-${message['text']}-$isRead',
                        ),
                        size: 15,
                        color: isRead
                            ? const Color(0xFF4FC3F7)
                            : Colors.white70,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
class NotificationListPage extends StatelessWidget {
  const NotificationListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F9FE),
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: const Color(0xFFF2F9FE),
      ),
      body: SafeArea(
        child: StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, authSnapshot) {
            if (authSnapshot.hasError) {
              return const _NotificationMessage(
                message: 'Could not verify your sign-in. Please try again.',
              );
            }
            if (authSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final user = authSnapshot.data;
            if (user == null) {
              return const _NotificationMessage(
                message: 'Sign in to view your notifications.',
              );
            }

            return _RecipientNotificationList(
              key: ValueKey(user.uid),
              recipientUid: user.uid,
            );
          },
        ),
      ),
    );
  }
}

class _RecipientNotificationList extends StatefulWidget {
  final String recipientUid;

  const _RecipientNotificationList({super.key, required this.recipientUid});

  @override
  State<_RecipientNotificationList> createState() =>
      _RecipientNotificationListState();
}

class _RecipientNotificationListState
    extends State<_RecipientNotificationList> {
  late final Stream<List<AppNotification>> _notifications;

  @override
  void initState() {
    super.initState();
    _notifications = NotificationService.instance.watchForRecipient(
      widget.recipientUid,
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AppNotification>>(
      stream: _notifications,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _NotificationMessage(
            message: 'Could not load notifications. Please try again.',
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final notifications = snapshot.data ?? const <AppNotification>[];
        if (notifications.isEmpty) {
          return const _NotificationMessage(
            message: 'You have no notifications yet.',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: notifications.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final notification = notifications[index];
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFD9EAF5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: const TextStyle(
                      color: darkBlue,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    notification.body,
                    style: const TextStyle(color: darkText, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatNotificationDate(notification.createdAt),
                    style: const TextStyle(color: greyText, fontSize: 12),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatNotificationDate(DateTime? dateTime) {
    if (dateTime == null) return 'Date unavailable';

    final local = dateTime.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '${local.year}-$month-$day · $hour:$minute $suffix';
  }
}

class _NotificationMessage extends StatelessWidget {
  final String message;

  const _NotificationMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}

// ============================================================
// CREATE ACCOUNT PAGE
// ============================================================

class CreateAccountPage extends StatefulWidget {
  const CreateAccountPage({super.key});

  @override
  State<CreateAccountPage> createState() => _CreateAccountPageState();
}

class _CreateAccountPageState extends State<CreateAccountPage> {
  bool isAgent = true;
  bool obscurePassword = true;
  bool obscureConfirmPassword = true;
  bool isCreatingAccount = false;

  final TextEditingController usernameController = TextEditingController();

  final TextEditingController emailController = TextEditingController();

  final TextEditingController idController = TextEditingController();

  final TextEditingController categoryController = TextEditingController();

  final TextEditingController passwordController = TextEditingController();

  final TextEditingController confirmPasswordController =
      TextEditingController();

  @override
  void dispose() {
    usernameController.dispose();
    emailController.dispose();
    idController.dispose();
    categoryController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  bool isValidEmail(String value) {
    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return emailPattern.hasMatch(value);
  }

  Future<void> _discardCreatedUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await FcmService.instance.unregisterCurrentDevice();
    try {
      await user.delete();
    } catch (_) {
      await FcmService.instance.signOut();
    }
  }

  Future<void> createAccount() async {
    final username = usernameController.text.trim();
    final email = emailController.text.trim();
    final userId = RegistrationIdValidator.normalize(idController.text);
    final category = categoryController.text.trim();
    final password = passwordController.text.trim();
    final confirmPassword = confirmPasswordController.text.trim();

    if (username.isEmpty) {
      _showMessage('Please enter your user name.');
      return;
    }

    if (email.isEmpty) {
      _showMessage('Please enter your email address.');
      return;
    }

    if (!isValidEmail(email)) {
      _showMessage('Please enter a valid email address.');
      return;
    }

    if (userId.isEmpty) {
      _showMessage(
        isAgent ? 'Please enter your Agent ID.' : 'Please enter your LO ID.',
      );
      return;
    }

    if (!RegistrationIdValidator.isValid(userId, isAgent: isAgent)) {
      _showMessage(RegistrationIdValidator.errorMessage(isAgent: isAgent));
      return;
    }

    if (isAgent && category.isEmpty) {
      _showMessage('Please select your Agent Category.');
      return;
    }

    if (password.isEmpty) {
      _showMessage('Please enter a password.');
      return;
    }

    if (password.length < 6) {
      _showMessage('Password must be at least 6 characters.');
      return;
    }

    if (password != confirmPassword) {
      _showMessage('Passwords do not match.');
      return;
    }

    setState(() {
      isCreatingAccount = true;
    });

    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (!mounted) {
        await _discardCreatedUser();
        return;
      }

      try {
        await AppStorage.saveProfile(
          username: username,
          email: email,
          role: isAgent ? 'Agent' : 'Liquidity Officer',
          id: userId,
          category: isAgent ? category : 'Liquidity Officer',
        );
      } catch (_) {
        await _discardCreatedUser();
        rethrow;
      }

      _showMessage(
        'Account created. Dashboard access will be available after authorization.',
      );

      await Future.delayed(const Duration(seconds: 2));

      if (!mounted) return;

      Navigator.pop(context);
    } on RegistrationIdAlreadyInUseException {
      if (!mounted) return;
      _showMessage('This ID is already registered. Please choose another ID.');
    } on RegistrationIdMismatchException {
      if (!mounted) return;
      _showMessage('This account already has a different registration ID.');
    } on RegistrationIdFormatException {
      if (!mounted) return;
      _showMessage(RegistrationIdValidator.errorMessage(isAgent: isAgent));
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;

      String message;

      switch (e.code) {
        case 'email-already-in-use':
          message = 'This email address is already registered.';
          break;

        case 'invalid-email':
          message = 'Please enter a valid email address.';
          break;

        case 'weak-password':
          message = 'The password is too weak. Please use a stronger password.';
          break;

        case 'network-request-failed':
          message =
              'Network connection failed. Please check your internet connection.';
          break;

        default:
          message =
              'Account creation failed. Please check your details and try again.';
      }

      _showMessage(message);
    } catch (e) {
      if (!mounted) return;

      _showMessage('Something went wrong while creating the account.');
    } finally {
      if (mounted) {
        setState(() {
          isCreatingAccount = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: darkBlue,
          duration: const Duration(seconds: 4),
        ),
      );
  }

  InputDecoration fieldDecoration(
    String label,
    IconData icon, {
    String? hintText,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      prefixIcon: Icon(icon, color: blue),
      filled: true,
      fillColor: paleBlue,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: darkBlue,
        title: const Text(
          'Create Account',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),

              const Text(
                'Create your Altrafloat account',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: darkBlue,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'Enter your details below to get started.',
                textAlign: TextAlign.center,
                style: TextStyle(color: greyText, fontSize: 15),
              ),

              const SizedBox(height: 25),

              // ROLE
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          isAgent = true;
                          idController.clear();
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: isAgent ? lightBlue : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isAgent ? blue : Colors.grey.shade300,
                          ),
                        ),
                        child: Text(
                          'Agent',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: isAgent ? darkBlue : greyText,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          isAgent = false;
                          categoryController.clear();
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: !isAgent ? lightBlue : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: !isAgent ? blue : Colors.grey.shade300,
                          ),
                        ),
                        child: Text(
                          'L.O.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: !isAgent ? darkBlue : greyText,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              TextField(
                controller: usernameController,
                decoration: fieldDecoration('User Name', Icons.person_outline),
              ),

              const SizedBox(height: 15),

              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                enableSuggestions: false,
                decoration: fieldDecoration(
                  'Email Address',
                  Icons.email_outlined,
                  hintText: 'Enter your email address',
                ),
              ),

              const SizedBox(height: 15),

              TextField(
                controller: idController,
                textCapitalization: TextCapitalization.characters,
                decoration: fieldDecoration(
                  isAgent ? 'Agent ID' : 'LO ID',
                  Icons.badge_outlined,
                  hintText:
                      isAgent
                          ? 'Example: G7123456'
                          : 'Example: S0123456 or C0123456',
                ),
              ),

              if (isAgent) ...[
                const SizedBox(height: 15),

                DropdownButtonFormField<String>(
                  value:
                      categoryController.text.isEmpty
                          ? null
                          : categoryController.text,
                  decoration: fieldDecoration(
                    'Agent Category',
                    Icons.category_outlined,
                  ),
                  items:
                      const [
                        'Main Agent',
                        'Cash Agent',
                        'Airtime Agent',
                        'Mobile Money Agent',
                      ].map((category) {
                        return DropdownMenuItem<String>(
                          value: category,
                          child: Text(category),
                        );
                      }).toList(),
                  onChanged: (value) {
                    setState(() {
                      categoryController.text = value ?? '';
                    });
                  },
                ),
              ],

              const SizedBox(height: 15),

              TextField(
                controller: passwordController,
                obscureText: obscurePassword,
                decoration: fieldDecoration(
                  'Password',
                  Icons.lock_outline,
                ).copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscurePassword ? Icons.visibility_off : Icons.visibility,
                      color: blue,
                    ),
                    onPressed: () {
                      setState(() {
                        obscurePassword = !obscurePassword;
                      });
                    },
                  ),
                ),
              ),

              const SizedBox(height: 15),

              TextField(
                controller: confirmPasswordController,
                obscureText: obscureConfirmPassword,
                decoration: fieldDecoration(
                  'Confirm Password',
                  Icons.lock_outline,
                ).copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscureConfirmPassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: blue,
                    ),
                    onPressed: () {
                      setState(() {
                        obscureConfirmPassword = !obscureConfirmPassword;
                      });
                    },
                  ),
                ),
              ),

              const SizedBox(height: 25),

              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: isCreatingAccount ? null : createAccount,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child:
                      isCreatingAccount
                          ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                          : const Text(
                            'Create Account',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                ),
              ),

              const SizedBox(height: 15),

              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text(
                  'Already have an account? Login',
                  style: TextStyle(color: blue, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AIManagerDashboard extends StatelessWidget {
  const AIManagerDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const LoginPage();
    }

    return FutureBuilder<IdTokenResult>(
      future: user.getIdTokenResult(true),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasError || snapshot.data?.claims?['aiManager'] != true) {
          return const Scaffold(
            body: Center(
              child: Text('Access denied. AI Manager authorization required.'),
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(title: const Text('Altrafloat AI Manager')),
          body: const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'AI Manager Dashboard\n\n'
                'Owner access verified.\n\n'
                'Administration tools will be added after security testing.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      },
    );
  }
}
