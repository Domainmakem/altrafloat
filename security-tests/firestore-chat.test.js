
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const {
  before,
  beforeEach,
  after,
  test,
} = require('node:test');
const assert = require('node:assert/strict');

const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');

const {
  doc,
  getDoc,
  setDoc,
  collection,
  addDoc,
  serverTimestamp,
  deleteDoc,
} = require('firebase/firestore');

const PROJECT_ID = 'demo-altrafloat';

const AGENT_UID = 'agent-test-001';
const LO_UID = 'lo-test-001';
const OTHER_AGENT_UID = 'agent-test-002';
const OTHER_LO_UID = 'lo-test-002';

const REQUEST_ID = 'accepted-request-001';

let testEnv;

before(async () => {
  const rules = fs.readFileSync(
    path.join(__dirname, '..', 'firestore.rules'),
    'utf8',
  );

  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      host: '127.0.0.1',
      port: 8080,
      rules,
    },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();

    await setDoc(doc(db, 'users', AGENT_UID), {
      uid: AGENT_UID,
      username: 'Test Agent',
      role: 'Agent',
      id: 'G7123456',
      category: 'Test',
      authorized: false,
    });

    await setDoc(doc(db, 'registrationIds', 'G7123456'), {
      uid: AGENT_UID,
      role: 'Agent',
    });

    await setDoc(doc(db, 'users', LO_UID), {
      uid: LO_UID,
      username: 'Test Officer',
      role: 'Liquidity Officer',
      id: 'S0123456',
      category: 'Test',
      authorized: true,
    });

    await setDoc(doc(db, 'registrationIds', 'S0123456'), {
      uid: LO_UID,
      role: 'Liquidity Officer',
    });

    await setDoc(doc(db, 'users', OTHER_AGENT_UID), {
      uid: OTHER_AGENT_UID,
      username: 'Other Agent',
      role: 'Agent',
      id: 'G7123457',
      category: 'Test',
      authorized: false,
    });

    await setDoc(doc(db, 'registrationIds', 'G7123457'), {
      uid: OTHER_AGENT_UID,
      role: 'Agent',
    });

    await setDoc(doc(db, 'users', OTHER_LO_UID), {
      uid: OTHER_LO_UID,
      username: 'Other Officer',
      role: 'Liquidity Officer',
      id: 'S0123457',
      category: 'Test',
      authorized: true,
    });

    await setDoc(doc(db, 'registrationIds', 'S0123457'), {
      uid: OTHER_LO_UID,
      role: 'Liquidity Officer',
    });

    await setDoc(doc(db, 'requests', REQUEST_ID), {
      agentUid: AGENT_UID,
      loUid: LO_UID,
      status: 'accepted',
    });
  });
});

after(async () => {
  if (testEnv) {
    await testEnv.cleanup();
  }
});

function authenticatedDb(uid) {
  return testEnv.authenticatedContext(uid).firestore();
}

function conversationData() {
  return {
    requestId: REQUEST_ID,
    agentUid: AGENT_UID,
    loUid: LO_UID,
    participantUids: [AGENT_UID, LO_UID],
    createdAt: serverTimestamp(),
  };
}

async function createConversation(uid = AGENT_UID) {
  const db = authenticatedDb(uid);

  await assertSucceeds(
    setDoc(
      doc(db, 'conversations', REQUEST_ID),
      conversationData(),
    ),
  );
}

test('Assigned Agent can check a missing conversation for an accepted request', async () => {
  const db = authenticatedDb(AGENT_UID);

  await assertSucceeds(
    getDoc(doc(db, 'conversations', REQUEST_ID)),
  );
});

test('Assigned Liquidity Officer can check a missing conversation for an accepted request', async () => {
  const db = authenticatedDb(LO_UID);

  await assertSucceeds(
    getDoc(doc(db, 'conversations', REQUEST_ID)),
  );
});

test('An unrelated Agent cannot check a missing conversation', async () => {
  const db = authenticatedDb(OTHER_AGENT_UID);

  await assertFails(
    getDoc(doc(db, 'conversations', REQUEST_ID)),
  );
});

test('An unrelated authorized Liquidity Officer cannot check a missing conversation', async () => {
  const db = authenticatedDb(OTHER_LO_UID);

  await assertFails(
    getDoc(doc(db, 'conversations', REQUEST_ID)),
  );
});

test('Agent can create a conversation for an accepted request', async () => {
  await createConversation(AGENT_UID);
});

test('Liquidity Officer can create a conversation for an accepted request', async () => {
  await createConversation(LO_UID);
});

test('Both participants can read an existing conversation', async () => {
  await createConversation();

  await assertSucceeds(
    getDoc(doc(authenticatedDb(AGENT_UID), 'conversations', REQUEST_ID)),
  );

  await assertSucceeds(
    getDoc(doc(authenticatedDb(LO_UID), 'conversations', REQUEST_ID)),
  );
});

test('An unrelated Agent cannot create a conversation', async () => {
  const db = authenticatedDb(OTHER_AGENT_UID);

  await assertFails(
    setDoc(
      doc(db, 'conversations', REQUEST_ID),
      conversationData(),
    ),
  );
});

test('An unrelated Agent cannot read an existing conversation', async () => {
  await createConversation();

  await assertFails(
    getDoc(
      doc(authenticatedDb(OTHER_AGENT_UID), 'conversations', REQUEST_ID),
    ),
  );
});

test('Participants cannot check a missing conversation while the request is pending', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), 'requests', REQUEST_ID),
      {
        agentUid: AGENT_UID,
        loUid: LO_UID,
        status: 'pending',
      },
    );
  });

  await assertFails(
    getDoc(doc(authenticatedDb(AGENT_UID), 'conversations', REQUEST_ID)),
  );

  await assertFails(
    getDoc(doc(authenticatedDb(LO_UID), 'conversations', REQUEST_ID)),
  );
});

test('A conversation cannot be created while its request is pending', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await setDoc(
      doc(context.firestore(), 'requests', REQUEST_ID),
      {
        agentUid: AGENT_UID,
        loUid: LO_UID,
        status: 'pending',
      },
    );
  });

  await assertFails(
    setDoc(
      doc(authenticatedDb(LO_UID), 'conversations', REQUEST_ID),
      conversationData(),
    ),
  );
});

test('A participant can send a message in an existing conversation', async () => {
  await createConversation();

  const db = authenticatedDb(AGENT_UID);

  await assertSucceeds(
    addDoc(collection(db, 'conversations', REQUEST_ID, 'messages'), {
      senderUid: AGENT_UID,
      text: 'Test message',
      createdAt: serverTimestamp(),
    }),
  );
});

test('An unrelated Agent cannot read conversation messages', async () => {
  await createConversation();

  await testEnv.withSecurityRulesDisabled(async (context) => {
    const adminDb = context.firestore();

    await setDoc(
      doc(
        adminDb,
        'conversations',
        REQUEST_ID,
        'messages',
        'message-1',
      ),
      {
        senderUid: AGENT_UID,
        text: 'Test message',
        createdAt: new Date(),
      },
    );
  });

  await assertFails(
    getDoc(
      doc(
        authenticatedDb(OTHER_AGENT_UID),
        'conversations',
        REQUEST_ID,
        'messages',
        'message-1',
      ),
    ),
  );
});

test('A participant cannot delete a message under the current rules', async () => {
  await createConversation();

  const messageRef = doc(
    authenticatedDb(AGENT_UID),
    'conversations',
    REQUEST_ID,
    'messages',
    'message-1',
  );

  await assertSucceeds(
    setDoc(messageRef, {
      senderUid: AGENT_UID,
      text: 'Test message',
      createdAt: serverTimestamp(),
    }),
  );

  await assertFails(deleteDoc(messageRef));
});
