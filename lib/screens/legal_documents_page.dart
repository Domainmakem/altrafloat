import 'package:material_ui/material_ui.dart';

const Color _altraBlue = Color(0xFF1F9CF0);
const Color _altraDarkBlue = Color(0xFF0B629D);

const String privacyPolicyVersion = '1.0';
const String termsConditionsVersion = '1.0';
const String legalDocumentsEffectiveDate = '1 January 2027';

const String privacyPolicyText = '''
ALTRAFLOAT

PRIVACY POLICY

Business Operator: AALTRA BLACK AND WHITE TRADING BUSINESS
Business Address: New Achimota, Tantra Hills, Greater Accra, Ghana
Support Email: altrafloat@gmail.com
Privacy Contact: altratradingbusiness@gmail.com
Effective Date: 1 January 2027
Launch Territory: Ghana
Minimum User Age: 18 years

Document Status: Draft for technical verification and final approval.


---

1. Introduction

AALTRA BLACK AND WHITE TRADING BUSINESS operates Altrafloat, a digital communication platform designed to connect Agents and Liquidity Officers.

We respect the privacy of our users and are committed to protecting personal information collected through the Altrafloat application.

This Privacy Policy explains what information we collect, why we collect it, how we use and protect it, when it may be shared, and the rights available to users.

Our data protection practices are governed by applicable Ghanaian data protection laws, including the Data Protection Act, 2012 (Act 843).

2. Eligibility

Altrafloat is intended exclusively for individuals aged 18 years and above.

Individuals under 18 years are not permitted to register or use the platform.

Altrafloat is initially intended for users within Ghana.

3. Information We Collect

Depending on the user's role and interaction with the application, Altrafloat may collect:

3.1 Registration and Account Information

- Username.
- Email address.
- Agent ID or Liquidity Officer ID.
- Agent category, where applicable.
- Account status and authorization information.
- Email verification status.

Phone numbers are not required during registration in the current version.

3.2 Authentication Information

Altrafloat uses Firebase Authentication for account authentication and password management.

Altrafloat does not store users' raw passwords in its own Firestore profile records.

Password changes and resets are managed through Firebase Authentication.

3.3 Communication Information

Altrafloat processes messages exchanged between Agents and Liquidity Officers.

Messages may contain:

- Requested transaction amounts.
- Mobile-money network information.
- Request details.
- Other information voluntarily shared by participants.

3.4 Device and Technical Information

The application may process:

- Device notification tokens.
- Device platform information.
- Notification registration information.
- Relevant technical information required for security and application functionality.

3.5 Security and Account Information

Altrafloat may process information relating to:

- Login and authentication events.
- Account authorization.
- Suspicious activities.
- Account restrictions and suspensions.
- Security investigations.
- Administrative actions.

The precise technical information collected by Firebase and other service providers will be described according to the services actually configured.

4. Information We Do Not Intentionally Collect

In the current application design:

- Registration does not require a phone number.
- The application does not request users' precise GPS location.
- The application does not intentionally collect approximate location for ordinary app functionality.
- The application does not process users' money or conduct money transfers.

Technical service providers may independently process network or security information, such as IP-related information, as necessary to provide their services. This must be verified against the actual configuration.

5. How We Use Personal Information

Altrafloat uses personal information for legitimate operational and security purposes, including:

1. Registering and authenticating users.
2. Verifying email addresses.
3. Managing Agent and Liquidity Officer accounts.
4. Managing Agent categories and Liquidity Officer authorization.
5. Facilitating communication between Agents and Liquidity Officers.
6. Processing and displaying requests.
7. Delivering application notifications.
8. Detecting suspicious activity.
9. Investigating complaints and reported misconduct.
10. Protecting accounts and platform security.
11. Responding to privacy requests.
12. Complying with applicable legal obligations.

6. How Altrafloat Handles Money Exchanges

Altrafloat provides a communication and coordination platform.

Money exchanges take place outside the application between the participating parties.

Altrafloat does not receive, hold, transfer or process the exchanged money through the application.

Transaction amounts and mobile-money network details may appear in messages exchanged between users.

7. Registration and Account Approval

Agents

Agents register, verify their email addresses and may access the application after successful verification.

Liquidity Officers

Liquidity Officers must verify their email addresses and wait for Altrafloat Admin approval before receiving account access.

Users will receive appropriate registration and authorization notifications.

8. Information Sharing

Altrafloat does not currently share users' personal information with advertising or marketing companies for advertising purposes.

Personal information may be processed by technology service providers necessary to operate the application.

These include Google and Firebase services.

The final list of service providers, their processing roles and applicable safeguards will be confirmed before publication.

Future advertising or marketing partnerships will require an updated privacy notice and any consent or other lawful basis required by applicable law.

Altrafloat does not authorize staff to disclose users' personal information outside the business without proper authorization or a lawful requirement.

9. International Data Processing

Altrafloat uses Google and Firebase services whose data centres are located outside Ghana.

Consequently, some personal information may be stored or processed outside Ghana.

Altrafloat will take appropriate steps to address applicable legal requirements and safeguards for international data transfers.

The exact countries and processing locations will depend on the configured services and their applicable terms.

10. Chat Privacy and Administrative Access

Messages exchanged between Agents and Liquidity Officers are intended to remain private between the participating users.

However, authorized Altrafloat personnel may review relevant messages when reasonably necessary to:

- Investigate complaints.
- Investigate suspected fraud.
- Address impersonation.
- Investigate security incidents.
- Resolve account-related disputes.

Access must be restricted to authorized personnel and legitimate administrative purposes.

Where appropriate and legally permitted, users will be notified when their messages are reviewed.

11. Fraud Prevention and Account Security

Altrafloat may use account and activity information to identify suspicious behaviour and help protect the platform.

Automated systems may identify unusual activity and trigger predefined warnings or restrictions.

The Altrafloat Admin may review cases and make administrative decisions.

Where automated findings and administrative reviews disagree, the Admin has final review authority.

Users may contact the Admin to request clarification or appeal account restrictions.

12. Account Suspension and Blocking

Altrafloat may temporarily restrict accounts during investigations.

Accounts confirmed to be involved in serious fraud, impersonation, repeated abuse or serious violations of platform rules may be permanently banned.

Affected users will receive appropriate notification, subject to applicable legal and security restrictions.

Users may appeal suspension or blocking decisions through the Altrafloat Admin.

13. Account Information Changes

Users may request changes to their registered email address and username, subject to appropriate verification and system rules.

Agents must contact the Admin to request changes to their Agent category.

Liquidity Officers must contact the Admin to request changes to their registered name or Liquidity Officer ID.

Users may change or reset their passwords through the available Firebase Authentication processes.

14. Notifications and Emails

Altrafloat uses in-app notifications for ordinary application activities, including:

- New requests.
- Request acceptance.
- Chat messages.

Account-related email notifications may include:

- Successful Agent registration.
- Liquidity Officer registration approval or rejection.
- Account suspension or reactivation.
- Password changes and resets.
- Email address changes.
- Security alerts.
- Account deletion notifications.
- Important Privacy Policy and Terms & Conditions updates.

The actual email service provider will be identified according to the final implementation.

Firebase and Resend are the proposed email-service options.

15. Account Inactivity and Deletion

Accounts belonging to Agents and Liquidity Officers may become eligible for deletion after two consecutive years without login.

Before permanent deletion:

1. The user will receive 30 days' advance notice.
2. A reminder will be sent after 15 days.
3. The account will remain accessible during the notice period.
4. The user may log in normally.
5. Logging in during the notice period cancels the pending deletion and restarts the two-year inactivity period.

This policy is subject to applicable legal requirements and necessary retention obligations.

16. Account Session Security

Altrafloat intends to automatically sign users out after 30 consecutive days without activity.

Users can log in again using their existing credentials.

Additional planned security measures include notifications for new or unrecognized devices and the ability to review and terminate unfamiliar sessions.

These measures will be described as operational features only after implementation is verified.

17. Data Retention

Altrafloat retains personal information for as long as reasonably necessary for the purposes for which it was collected.

Information may be retained while an account remains active.

After account deletion, limited information may be retained where necessary to:

- Meet legal obligations.
- Resolve disputes.
- Investigate fraud.
- Address security incidents.
- Protect the rights of Altrafloat and its users.

Privacy-request records are intended to be retained for three years after resolution, subject to applicable legal requirements.

Specific retention periods for messages, device tokens, authentication records and other data will be established and verified before publication.

18. User Privacy Rights

Subject to applicable law, users may request:

1. Access to their personal information.
2. Correction of inaccurate or outdated information.
3. Deletion of personal information.
4. Information about how their information is processed.
5. Withdrawal of consent for optional processing.
6. An objection to applicable processing activities.
7. Review of significant decisions made through automated processing.

Withdrawing consent for optional activities, such as future marketing, should not automatically result in loss of ordinary account access.

Some information may need to be retained where required by law or necessary for legitimate security and legal purposes.

19. Privacy Requests

Users may submit privacy requests to:

altratradingbusiness@gmail.com

Altrafloat intends to:

- Acknowledge receipt by email.
- Verify the identity of the requester.
- Review the request.
- Aim to respond within 30 days, subject to applicable legal deadlines.
- Explain any delay and provide an expected response date where necessary.

The business will maintain records of privacy requests and their resolution.

20. Staff Access and Confidentiality

Access to personal information is restricted to authorized personnel.

Altrafloat intends to require:

- Individual staff login credentials.
- Access limited to assigned responsibilities.
- Confidentiality agreements.
- Data-protection training.
- Proper authorization before external disclosure.

Shared staff credentials should not be used to access personal information.

21. Security Measures

Altrafloat uses Firebase and other appropriate technical services to support account authentication, data storage and notifications.

The business will maintain appropriate technical and organizational safeguards to protect personal information against unauthorized access, loss, misuse, alteration or disclosure.

No electronic system can guarantee absolute security.

Security incidents will be handled in accordance with applicable legal obligations. Users and the Data Protection Commission will be notified where required by law.

22. Advertising and Marketing

Altrafloat does not currently operate the proposed external advertising and marketing data-sharing arrangement.

If advertising or marketing partnerships are introduced in the future, the Privacy Policy will be updated to explain the relevant information processing, recipients, purposes and available user choices.

23. Third-Party Services

Altrafloat relies on third-party technology services, including Google and Firebase.

Other service providers may be introduced where necessary for application functionality.

Their involvement and relevant data-processing arrangements will be reviewed before implementation.

24. Privacy Complaints

Users who believe their personal information has been mishandled may contact Altrafloat through:

altratradingbusiness@gmail.com

Users may also complain to Ghana's Data Protection Commission.

The Commission is responsible for overseeing compliance with Ghana's Data Protection Act, 2012 (Act 843).

Official website: https://dpc.gov.gh/

25. Updates to This Privacy Policy

Altrafloat may update this Privacy Policy when its operations, technology, services or legal obligations change.

Users will receive email notifications when the Privacy Policy is updated.

Notifications will include a summary of important changes and information about where to read the updated document.

Previous versions will remain available for reference in the application's Privacy & Security section.

The documents will be provided in English at launch.

26. Contact Information

For privacy-related requests:

Email: altratradingbusiness@gmail.com

For general application support:

Email: altrafloat@gmail.com

Business Operator: AALTRA BLACK AND WHITE TRADING BUSINESS

Address: New Achimota, Tantra Hills, Greater Accra, Ghana.


---

End of Privacy Policy Draft''';

const String termsConditionsText = '''
ALTRAFLOAT

TERMS & CONDITIONS

Business Operator: AALTRA BLACK AND WHITE TRADING BUSINESS
Business Address: New Achimota, Tantra Hills, Greater Accra, Ghana
Support Email: altrafloat@gmail.com
Privacy Email: altratradingbusiness@gmail.com
Effective Date: 1 January 2027
Territory: Ghana
Minimum Age: 18 years

Document Status: Draft for application integration and legal review.


---

1. Agreement to These Terms

These Terms & Conditions govern access to and use of the Altrafloat application.

By registering for or using Altrafloat, users agree to comply with these Terms & Conditions and the applicable Privacy Policy.

Users who do not agree to these terms must not use the application.

2. About Altrafloat

Altrafloat is a digital communication and coordination platform operated by AALTRA BLACK AND WHITE TRADING BUSINESS.

The platform connects two principal categories of users:

- Agents.
- Liquidity Officers.

Its purpose is to facilitate communication, request submission, request acceptance and coordination between registered users.

Altrafloat is not a party to private arrangements independently made between users.

3. Eligibility Requirements

To register and use Altrafloat, an individual must:

1. Be at least 18 years old.
2. Be located in Ghana and eligible to use the service.
3. Provide accurate registration information.
4. Have a valid email address.
5. Complete the required email verification.
6. Agree to follow these Terms & Conditions.

Providing false age, identity or registration information is prohibited.

4. User Registration and Account Authorization

4.1 Agents

Agents must:

- Complete the required registration information.
- Provide their assigned Agent ID.
- Select the applicable Agent category.
- Verify their email address.

After successful email verification, Agents may access the application, subject to account security and authorization controls.

4.2 Liquidity Officers

Liquidity Officers must:

- Complete the required registration information.
- Provide their assigned Liquidity Officer ID.
- Verify their email address.
- Wait for Admin approval.

A Liquidity Officer cannot access restricted application features until the Admin approves the account.

4.3 Account Accuracy

Users must provide accurate and current information.

Users must not impersonate another person or register using another person's identity or credentials.

5. Account Security

Users are responsible for:

- Protecting their login credentials.
- Keeping their email account secure.
- Not sharing their passwords.
- Reporting suspected unauthorized access.
- Not allowing unauthorized persons to use their accounts.

Passwords are managed through Firebase Authentication.

Users may change their passwords or request password resets through the available authentication features.

Users should contact the Admin if they suspect their accounts have been compromised.

6. Account Information Changes

Users may request or make permitted changes to their usernames and email addresses, subject to account verification and system controls.

Agents must contact the Admin to request changes to their Agent category.

Liquidity Officers must contact the Admin to request changes to their registered names or Liquidity Officer IDs.

Changes requiring Admin approval will not take effect until approved.

7. Platform Communication

Altrafloat provides communication tools through which Agents and Liquidity Officers may:

- Submit requests.
- Receive and accept requests.
- Exchange messages.
- Discuss requested amounts.
- Identify mobile-money networks.
- Coordinate arrangements outside the application.

Users must communicate honestly, respectfully and responsibly.

8. Money Exchanges Outside Altrafloat

Altrafloat is a communication and coordination platform.

Money exchanges between Agents and Liquidity Officers take place outside the application.

Altrafloat does not receive, hold, safeguard, transfer or process the money exchanged between users through the application.

Altrafloat does not operate an in-app wallet or escrow service under the current service model.

Users are responsible for independently checking the identity and relevant details of the person with whom they arrange an exchange.

Users must independently verify transaction details before proceeding.

Altrafloat does not guarantee that another user will complete an arrangement or fulfil an independently agreed obligation.

Nothing in this section removes any responsibility or liability that applicable law places on Altrafloat.

9. User Responsibilities

Every user agrees to:

1. Use Altrafloat only for lawful purposes.
2. Provide truthful information.
3. Respect other users.
4. Protect their account credentials.
5. Avoid misleading requests.
6. Avoid impersonation.
7. Avoid fraudulent conduct.
8. Report suspicious activities.
9. Respect the privacy of other users.
10. Follow Admin instructions relating to legitimate security investigations.

Users must not misuse the application to deceive, threaten, harass or exploit others.

10. Prohibited Activities

The following activities are prohibited:

- Identity theft.
- Impersonation.
- Fraudulent requests.
- Deliberately misleading another user.
- Unauthorized access to accounts.
- Sharing another person's private information without authorization.
- Harassment or abusive communication.
- Manipulating application requests.
- Circumventing account restrictions.
- Attempting to compromise application security.
- Using the platform for unlawful activities.
- Interfering with the operation of Altrafloat.

Altrafloat may investigate suspected violations and take appropriate action.

11. Admin Authority

The Altrafloat Admin is responsible for overseeing account authorization, platform administration, complaints and enforcement of these terms.

The Admin may:

- Review registration information.
- Approve or reject Liquidity Officer registrations.
- Review reported user activity.
- Investigate complaints.
- Review relevant chat records for legitimate investigative purposes.
- Restrict accounts during investigations.
- Suspend accounts.
- Reinstate accounts.
- Permanently ban accounts where justified.

Administrative actions must be taken for legitimate operational, security or compliance purposes.

12. Complaints and Reporting

Users should report:

- Suspected fraud.
- Impersonation.
- Harassment.
- Suspicious requests.
- Unauthorized account access.
- Misuse of personal information.
- Other violations of these terms.

Reports may be submitted through the in-app Admin support channel.

Users should provide sufficient information to enable the Admin to investigate.

13. Account Restrictions and Suspension

Altrafloat may temporarily restrict or suspend an account where necessary to:

- Investigate suspected fraud.
- Protect other users.
- Investigate impersonation.
- Address security concerns.
- Prevent continued misuse.
- Comply with legal obligations.

Where appropriate, the affected user will receive an email explaining the restriction and how to contact the Admin.

14. Appeals and Account Reviews

Users may contact the Altrafloat Admin to request clarification or appeal a suspension, restriction or blocking decision.

The Admin may review the available information and determine whether the restriction should remain, be modified or be removed.

A serious violation may result in permanent account termination.

15. Account Inactivity

Accounts that remain without a successful login for two consecutive years may become eligible for deletion.

Before deletion:

- A 30-day advance email notice will be sent.
- A reminder will be sent after 15 days.
- The account will remain accessible during the notice period.
- A successful login during the notice period cancels the pending deletion.
- The two-year inactivity period then restarts from the latest successful login.

This applies equally to Agents and Liquidity Officers.

16. Account Termination

Altrafloat may suspend or terminate an account where:

- A user seriously violates these terms.
- An account is involved in confirmed fraudulent activity.
- A user engages in impersonation.
- A user repeatedly abuses the platform.
- Continued access presents a security risk.
- Termination is required by law.

Where appropriate, users will receive notification of the action.

Users may contact the Admin to request clarification or appeal where an appeal is available.

17. Chat and Communication Records

Messages exchanged through Altrafloat are intended for communication between the participating users.

Users must not misuse or unlawfully disclose messages or information obtained through the platform.

Authorized Admin personnel may review relevant communication records when necessary to investigate complaints, fraud, impersonation, security incidents or disputes.

Such access is subject to the Privacy Policy and applicable law.

18. Notifications

Altrafloat uses in-app notifications for ordinary platform activities, including:

- New requests.
- Accepted requests.
- New chat messages.

Email notifications may be used for important account-related matters, including:

- Registration and account activation.
- Liquidity Officer approval or rejection.
- Password changes and resets.
- Security alerts.
- Account restrictions.
- Account status changes.
- Policy updates.

The availability of individual notification features depends on the application's implementation.

19. Service Availability

Altrafloat will make reasonable efforts to maintain application availability and reliability.

However, uninterrupted service cannot be guaranteed.

The application may occasionally be unavailable because of:

- Scheduled maintenance.
- Technical failures.
- Internet connectivity problems.
- Third-party service interruptions.
- Security incidents.
- Other circumstances beyond reasonable control.

Altrafloat may modify, suspend or discontinue particular features where reasonably necessary.

20. Third-Party Services

Altrafloat relies on third-party technology providers, including Google and Firebase.

Other service providers may support email delivery, notifications, authentication and application operations.

Their use is subject to applicable third-party terms and the Altrafloat Privacy Policy.

21. Privacy and Personal Information

Users' personal information is handled according to the Altrafloat Privacy Policy.

The Privacy Policy explains:

- What information is collected.
- Why information is collected.
- How information is stored and processed.
- When information may be shared.
- How long information may be retained.
- Users' privacy rights.
- How to submit privacy requests.

Users should read the Privacy Policy before using Altrafloat.

22. Intellectual Property

The Altrafloat application, its branding, logos, designs, software and original content are owned by or lawfully used by AALTRA BLACK AND WHITE TRADING BUSINESS or the relevant rights holders.

Users may not copy, reproduce, modify, distribute or commercially exploit protected application materials without appropriate permission.

Nothing in these terms transfers ownership of Altrafloat's intellectual property to users.

23. Limitation of Responsibility

Altrafloat provides communication and coordination services.

It does not guarantee:

- The honesty of every user.
- The financial ability of another user.
- Completion of an independently arranged exchange.
- The accuracy of information voluntarily supplied by another user.
- The availability of another user's services.
- The outcome of private arrangements between users.

Users remain responsible for their own decisions and independently arranged exchanges.

Nothing in these Terms & Conditions excludes liability that cannot legally be excluded under applicable Ghanaian law.

24. Disputes

Users should initially report platform-related complaints to the Altrafloat Admin.

The Admin may investigate and attempt to resolve complaints involving application access, account authorization, communication or violations of these terms.

Disputes concerning independent money exchanges between users should be addressed by the parties through the appropriate legal or dispute-resolution channels.

Nothing in these terms prevents a user from exercising legal rights or contacting a relevant regulatory authority.

25. Changes to These Terms

Altrafloat may update these Terms & Conditions when necessary.

Users will receive email notifications when important updates are published.

Notifications will include a summary of important changes and information about where to read the updated terms.

Current and previous versions will be available through:

Settings → Privacy & Security

Policy updates will not automatically require users to accept a new checkbox merely because a document has changed. Any additional agreement required by law or for a material change to the service will be handled appropriately.

26. Governing Law

These Terms & Conditions are governed by the applicable laws of the Republic of Ghana.

Any legal proceedings will be handled by a court or other competent authority with jurisdiction under applicable Ghanaian law.

27. Contact Information

For general support and account-related concerns:

altrafloat@gmail.com

For privacy-related requests:

altratradingbusiness@gmail.com

Business Operator: AALTRA BLACK AND WHITE TRADING BUSINESS

Address: New Achimota, Tantra Hills, Greater Accra, Ghana.


---

END OF ALTRAFLOAT TERMS & CONDITIONS''';

class PrivacySecurityPage extends StatelessWidget {
  const PrivacySecurityPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy & Security'),
        backgroundColor: const Color(0xFFF2F9FE),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Legal Documents',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _altraDarkBlue,
                ),
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                color: const Color(0xFFF7FBFF),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: _altraBlue.withValues(alpha: 0.2)),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(
                        Icons.privacy_tip_outlined,
                        color: _altraBlue,
                      ),
                      title: const Text('Altrafloat Privacy Policy'),
                      subtitle: const Text(
                        'Version $privacyPolicyVersion • Effective $legalDocumentsEffectiveDate',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const PrivacyPolicyPage(),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(
                        Icons.description_outlined,
                        color: _altraBlue,
                      ),
                      title: const Text('Altrafloat Terms & Conditions'),
                      subtitle: const Text(
                        'Version $termsConditionsVersion • Effective $legalDocumentsEffectiveDate',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const TermsConditionsPage(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LegalDocumentScaffold(
      appBarTitle: 'Privacy Policy',
      documentTitle: 'Altrafloat Privacy Policy',
      version: privacyPolicyVersion,
      effectiveDate: legalDocumentsEffectiveDate,
      content: privacyPolicyText,
    );
  }
}

class TermsConditionsPage extends StatelessWidget {
  const TermsConditionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _LegalDocumentScaffold(
      appBarTitle: 'Terms & Conditions',
      documentTitle: 'Altrafloat Terms & Conditions',
      version: termsConditionsVersion,
      effectiveDate: legalDocumentsEffectiveDate,
      content: termsConditionsText,
    );
  }
}

class _LegalDocumentScaffold extends StatelessWidget {
  final String appBarTitle;
  final String documentTitle;
  final String version;
  final String effectiveDate;
  final String content;

  const _LegalDocumentScaffold({
    required this.appBarTitle,
    required this.documentTitle,
    required this.version,
    required this.effectiveDate,
    required this.content,
  });

  static final RegExp _numberedSectionPattern = RegExp(r'^\d+\.\s+.+');
  static final RegExp _subSectionPattern = RegExp(r'^\d+\.\d+\s+.+');
  static final RegExp _linkOrEmailPattern = RegExp(
    r'(https?:\/\/[^\s]+|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})',
  );

  @override
  Widget build(BuildContext context) {
    final blocks = _parseLines(content);
    return Scaffold(
      appBar: AppBar(
        title: Text(appBarTitle),
        backgroundColor: const Color(0xFFF2F9FE),
      ),
      body: SafeArea(
        child: Scrollbar(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2F9FE),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _altraBlue.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            documentTitle,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: _altraDarkBlue,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Version $version • Effective Date: $effectiveDate',
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    ...blocks,
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _parseLines(String rawText) {
    final lines = rawText.split('\n');
    final widgets = <Widget>[];

    for (final rawLine in lines) {
      final line = rawLine.trimRight();
      if (line.trim().isEmpty) {
        widgets.add(const SizedBox(height: 8));
        continue;
      }

      if (line.trim() == '---') {
        widgets.add(
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(thickness: 1),
          ),
        );
        continue;
      }

      if (line == 'ALTRAFLOAT' ||
          line == 'PRIVACY POLICY' ||
          line == 'TERMS & CONDITIONS') {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: SelectableText(
              line,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: _altraDarkBlue,
                letterSpacing: 0.4,
              ),
            ),
          ),
        );
        continue;
      }

      if (_subSectionPattern.hasMatch(line)) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: SelectableText(
              line,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _altraDarkBlue,
              ),
            ),
          ),
        );
        continue;
      }

      if (_numberedSectionPattern.hasMatch(line)) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 6),
            child: SelectableText(
              line,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _altraDarkBlue,
              ),
            ),
          ),
        );
        continue;
      }

      if (line.startsWith('- ')) {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(left: 12, top: 2, bottom: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SelectableText(
                  '- ',
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.55,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                Expanded(
                  child: _buildRichLine(line.substring(2)),
                ),
              ],
            ),
          ),
        );
        continue;
      }

      if (line == 'Agents' ||
          line == 'Liquidity Officers' ||
          line == 'End of Privacy Policy Draft' ||
          line == 'END OF ALTRAFLOAT TERMS & CONDITIONS') {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: SelectableText(
              line,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
          ),
        );
        continue;
      }

      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: _buildRichLine(line),
        ),
      );
    }

    return widgets;
  }

  Widget _buildRichLine(String line) {
    const baseStyle = TextStyle(
      fontSize: 15,
      height: 1.55,
      color: Colors.black87,
    );
    final matches = _linkOrEmailPattern.allMatches(line).toList();
    if (matches.isEmpty) {
      return SelectableText(line, style: baseStyle);
    }

    final spans = <InlineSpan>[];
    var currentIndex = 0;
    for (final match in matches) {
      if (match.start > currentIndex) {
        spans.add(TextSpan(text: line.substring(currentIndex, match.start)));
      }
      spans.add(
        TextSpan(
          text: match.group(0),
          style: const TextStyle(
            color: _altraDarkBlue,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
          ),
        ),
      );
      currentIndex = match.end;
    }
    if (currentIndex < line.length) {
      spans.add(TextSpan(text: line.substring(currentIndex)));
    }

    return SelectableText.rich(
      TextSpan(style: baseStyle, children: spans),
    );
  }
}
