import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:altrafloat/main.dart';
import 'package:altrafloat/screens/legal_documents_page.dart';

void main() {
  testWidgets(
    'Privacy & Security opens Privacy Policy and Terms & Conditions with exact text',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PrivacySecurityPage(),
        ),
      );

      expect(find.byType(PrivacySecurityPage), findsOneWidget);
      expect(find.text('Altrafloat Privacy Policy'), findsOneWidget);
      expect(find.text('Altrafloat Terms & Conditions'), findsOneWidget);
      expect(
        find.text('Version 1.0 • Effective 1 January 2027'),
        findsNWidgets(2),
      );

      await tester.tap(find.text('Altrafloat Privacy Policy'));
      await tester.pumpAndSettle();

      expect(find.byType(PrivacyPolicyPage), findsOneWidget);
      expect(find.text('PRIVACY POLICY'), findsOneWidget);
      expect(
        find.text('Version 1.0 • Effective Date: 1 January 2027'),
        findsOneWidget,
      );
      expect(privacyPolicyText, startsWith('ALTRAFLOAT\n\nPRIVACY POLICY'));
      expect(privacyPolicyText, endsWith('End of Privacy Policy Draft'));
      expect(privacyPolicyText, contains('https://dpc.gov.gh/'));
      expect(privacyPolicyText, contains('altrafloat@gmail.com'));
      expect(privacyPolicyText, contains('altratradingbusiness@gmail.com'));

      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Altrafloat Terms & Conditions'));
      await tester.pumpAndSettle();

      expect(find.byType(TermsConditionsPage), findsOneWidget);
      expect(find.text('TERMS & CONDITIONS'), findsOneWidget);
      expect(
        find.text('Version 1.0 • Effective Date: 1 January 2027'),
        findsOneWidget,
      );
      expect(
        termsConditionsText,
        startsWith('ALTRAFLOAT\n\nTERMS & CONDITIONS'),
      );
      expect(
        termsConditionsText,
        endsWith('END OF ALTRAFLOAT TERMS & CONDITIONS'),
      );
      expect(termsConditionsText, contains('Settings → Privacy & Security'));
      expect(termsConditionsText, contains('altrafloat@gmail.com'));
      expect(termsConditionsText, contains('altratradingbusiness@gmail.com'));
    },
  );

  testWidgets('LoginPage does not show mandatory policy acceptance checkboxes', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
    await tester.pumpAndSettle();

    expect(find.text('I accept the Privacy Policy'), findsNothing);
    expect(find.text('I accept the Terms and Conditions'), findsNothing);
  });
}
