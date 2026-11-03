// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:altrafloat/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('login screen shows email and username fields', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AltrafloatApp());

    expect(find.text('User Name'), findsOneWidget);
    expect(find.text('Email Address'), findsOneWidget);
    expect(find.text('Enter your email address'), findsOneWidget);
  });

  testWidgets('create account screen includes a real email field', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: CreateAccountPage()));

    expect(find.text('Email Address'), findsOneWidget);
    expect(find.text('Enter your email address'), findsOneWidget);
  });

  test('registration IDs follow the role-specific formats', () {
    expect(RegistrationIdValidator.isValid('G7123456', isAgent: true), isTrue);
    expect(RegistrationIdValidator.isValid('G71234567', isAgent: true), isTrue);
    expect(RegistrationIdValidator.isValid('S0123456', isAgent: false), isTrue);
    expect(
      RegistrationIdValidator.isValid('C01234567', isAgent: false),
      isTrue,
    );

    expect(RegistrationIdValidator.isValid('G712345', isAgent: true), isFalse);
    expect(RegistrationIdValidator.isValid('G0123456', isAgent: true), isFalse);
    expect(RegistrationIdValidator.isValid('S012345', isAgent: false), isFalse);
    expect(
      RegistrationIdValidator.isValid('LO123456', isAgent: false),
      isFalse,
    );
    expect(RegistrationIdValidator.isValid('S0123456', isAgent: true), isFalse);
  });

  test('Agents can access their dashboard without manual authorization', () {
    const agentProfile = {
      'uid': 'agent-uid',
      'role': 'Agent',
      'id': 'G7123456',
      'authorized': false,
    };

    expect(
      AppStorage.isAuthorizedProfile(
        agentProfile,
        uid: 'agent-uid',
        role: 'Agent',
      ),
      isTrue,
    );
    expect(
      AppStorage.matchesProfile(
        agentProfile,
        uid: 'agent-uid',
        role: 'Agent',
        id: 'G7123456',
      ),
      isTrue,
    );
    expect(
      AppStorage.isAuthorizedProfile(
        {...agentProfile, 'authorized': true},
        uid: 'agent-uid',
        role: 'Agent',
        id: 'G7123456',
      ),
      isTrue,
    );
  });

  test('unauthorized LO cannot access the LO dashboard', () {
    const loProfile = {
      'uid': 'lo-uid',
      'role': 'Liquidity Officer',
      'id': 'S0123456',
      'authorized': false,
    };

    expect(
      AppStorage.isAuthorizedProfile(
        loProfile,
        uid: 'lo-uid',
        role: 'Liquidity Officer',
      ),
      isFalse,
    );
    expect(
      AppStorage.matchesProfile(
        loProfile,
        uid: 'lo-uid',
        role: 'Liquidity Officer',
        id: 'S0123456',
      ),
      isTrue,
    );
  });

  test('authorized LO can access the LO dashboard', () {
    const loProfile = {
      'uid': 'lo-uid',
      'role': 'Liquidity Officer',
      'id': 'C01234567',
      'authorized': true,
    };

    expect(
      AppStorage.isAuthorizedProfile(
        loProfile,
        uid: 'lo-uid',
        role: 'Liquidity Officer',
        id: 'C01234567',
      ),
      isTrue,
    );
  });

  test('dashboard authorization still requires matching role and ID', () {
    const agentProfile = {
      'uid': 'agent-uid',
      'role': 'Agent',
      'id': 'G7123456',
      'authorized': false,
    };

    expect(
      AppStorage.isAuthorizedProfile(
        agentProfile,
        uid: 'agent-uid',
        role: 'Liquidity Officer',
      ),
      isFalse,
    );
    expect(
      AppStorage.isAuthorizedProfile(
        agentProfile,
        uid: 'other-uid',
        role: 'Agent',
      ),
      isFalse,
    );
    expect(
      AppStorage.isAuthorizedProfile(
        agentProfile,
        uid: 'agent-uid',
        role: 'Agent',
        id: 'G71234567',
      ),
      isFalse,
    );
  });

  testWidgets('agent dashboard has no bottom overflow', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(600, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MaterialApp(home: AgentDashboard()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('LO dashboard has no bottom overflow', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(600, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      const MaterialApp(home: LiquidityOfficerDashboard()),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('chat aligns by role and shows read receipts', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await AppStorage.saveChatMessages([
      {
        'sender': 'Agent One',
        'senderRole': 'Agent',
        'text': 'Unread agent message',
        'time': '09:00 AM',
        'chatId': 'test_chat',
        'read': 'false',
      },
      {
        'sender': 'Agent One',
        'senderRole': 'Agent',
        'text': 'Read agent message',
        'time': '09:01 AM',
        'chatId': 'test_chat',
        'read': 'true',
      },
      {
        'sender': 'LO One',
        'senderRole': 'Liquidity Officer',
        'text': 'LO response',
        'time': '09:02 AM',
        'chatId': 'test_chat',
        'read': 'false',
      },
    ]);

    await tester.pumpWidget(
      const MaterialApp(
        home: ChatPage(
          currentUser: 'Agent One',
          currentRole: 'Agent',
          otherUser: 'LO One',
          otherRole: 'Liquidity Officer',
          chatId: 'test_chat',
        ),
      ),
    );
    await tester.pumpAndSettle();

    Align messageAlignment(String text) {
      final messageFinder = find.byKey(ValueKey('chat-message-$text'));
      return tester.widget<Align>(
        find.ancestor(of: messageFinder, matching: find.byType(Align)).first,
      );
    }

    expect(
      messageAlignment('Unread agent message').alignment,
      Alignment.centerLeft,
    );
    expect(
      messageAlignment('Read agent message').alignment,
      Alignment.centerLeft,
    );
    expect(messageAlignment('LO response').alignment, Alignment.centerRight);

    final unreadCheck = tester.widget<Icon>(
      find.byKey(const ValueKey('chat-read-Unread agent message-false')),
    );
    final readCheck = tester.widget<Icon>(
      find.byKey(const ValueKey('chat-read-Read agent message-true')),
    );
    expect(unreadCheck.icon, Icons.check);
    expect(readCheck.icon, Icons.done_all);
    expect(readCheck.color, const Color(0xFF4FC3F7));

    final savedMessages = await AppStorage.loadChatMessages();
    expect(
      savedMessages.singleWhere(
        (message) => message['text'] == 'LO response',
      )['read'],
      'true',
    );
  });

  test('dashboard profile and chat data persist locally', () async {
    SharedPreferences.setMockInitialValues({});

    await AppStorage.saveProfile(
      username: 'Altrafloat Agent',
      email: 'agent@altrafloat.com',
      role: 'Agent',
      id: 'G7123456',
      category: 'Main Agent',
    );

    await AppStorage.saveChatMessages([
      {'sender': 'agent', 'text': 'Hello LO', 'time': '09:00 AM'},
    ]);

    final profile = await AppStorage.loadProfile();
    final chat = await AppStorage.loadChatMessages();

    expect(profile['username'], 'Altrafloat Agent');
    expect(profile['id'], 'G7123456');
    expect(profile['authorized'], 'false');
    expect(chat.first['text'], 'Hello LO');
  });
}
