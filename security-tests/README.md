
# Altrafloat Firestore Security Tests

These tests check the Firestore security rules using the local Firebase
Firestore Emulator.

They do not connect to or modify the live Firebase project.

## Requirements

- Node.js 20 or later
- npm
- Java, as required by the Firestore Emulator

## Install

From this directory:

    npm install

## Run the tests

From this directory:

    npm run test:emulator

The command starts the Firestore Emulator, runs the tests, and stops
the emulator afterwards.

The emulator uses the demo project ID:

    demo-altrafloat

It does not target altrafloat-gen-z.

## Rules under test

The test suite reads:

    ../firestore.rules

Changing the rules in the repository will therefore change the rules
used by the next test run.

## Test coverage

The initial tests cover:

- Initial conversation reads by an Agent and Liquidity Officer.
- Conversation creation for an accepted request.
- Access by both legitimate participants.
- Rejection of unrelated users.
- Rejection of conversation creation for pending requests.
- Message creation and access.
- Message deletion restrictions.

## Important

The initial conversation-read tests intentionally record the current
rules' behaviour. They are not a proposed security-rule correction.

Do not deploy rules as part of running these tests.
