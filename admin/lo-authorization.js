'use strict';

const LO_ROLE = 'Liquidity Officer';
const LO_ID_PATTERN = /^(S0|C0)[0-9]{6,7}$/;

function validateLORecord(uid, profile, claim) {
  if (!uid || !profile || profile.uid !== uid) {
    throw new Error(`users/${uid || '<missing>'} is missing or has a mismatched uid.`);
  }
  if (profile.role !== LO_ROLE) {
    throw new Error(`users/${uid}.role must be "${LO_ROLE}".`);
  }
  if (typeof profile.id !== 'string' || !LO_ID_PATTERN.test(profile.id)) {
    throw new Error(`users/${uid}.id is not a valid LO registration ID.`);
  }
  if (typeof profile.username !== 'string' || !profile.username.trim()) {
    throw new Error(`users/${uid}.username must be a non-empty string.`);
  }
  if (typeof profile.authorized !== 'boolean') {
    throw new Error(`users/${uid}.authorized must be a boolean.`);
  }
  if (!claim || claim.uid !== uid || claim.role !== LO_ROLE) {
    throw new Error(`registrationIds/${profile.id} does not claim this LO profile.`);
  }
  return profile;
}

async function updateLOAuthorization({
  db,
  fieldValue,
  uid,
  operation,
  dryRun = false,
}) {
  if (!['approve', 'revoke', 'migrate'].includes(operation)) {
    throw new Error(`Unsupported operation: ${operation}`);
  }
  if (!uid) throw new Error('A LO uid is required.');

  const profileRef = db.collection('users').doc(uid);
  const availabilityRef = db.collection('loAvailability').doc(uid);

  return db.runTransaction(async (transaction) => {
    const profileSnapshot = await transaction.get(profileRef);
    if (!profileSnapshot.exists) {
      throw new Error(`users/${uid} does not exist.`);
    }
    const profile = profileSnapshot.data();
    if (typeof profile.id !== 'string') {
      throw new Error(`users/${uid}.id is missing or invalid.`);
    }
    const claimRef = db.collection('registrationIds').doc(profile.id);
    const [claimSnapshot, availabilitySnapshot] = await Promise.all([
      transaction.get(claimRef),
      transaction.get(availabilityRef),
    ]);
    const claim = claimSnapshot.exists ? claimSnapshot.data() : null;
    validateLORecord(uid, profile, claim);

    const authorized =
      operation === 'approve'
        ? true
        : operation === 'revoke'
          ? false
          : profile.authorized;
    const timestamp = fieldValue.serverTimestamp();
    const currentAvailability = availabilitySnapshot.exists
      ? availabilitySnapshot.data()
      : {};
    const existingCreatedAt = currentAvailability.createdAt;
    const projection = {
      uid,
      role: LO_ROLE,
      name: profile.username.trim(),
      id: profile.id,
      idValid: true,
      available: false,
      authorized,
      createdAt:
        existingCreatedAt &&
        typeof existingCreatedAt.toDate === 'function'
          ? existingCreatedAt
          : timestamp,
      updatedAt: timestamp,
    };

    if (!dryRun) {
      if (operation !== 'migrate') {
        transaction.set(
          profileRef,
          { authorized, updatedAt: timestamp },
          { merge: true },
        );
      }
      transaction.set(availabilityRef, projection);
    }

    return {
      uid,
      operation,
      dryRun,
      authorized,
      availability: projection,
      writes: dryRun ? 0 : operation === 'migrate' ? 1 : 2,
    };
  });
}

function parseArgs(argv) {
  if (argv.length === 1 && ['--help', '-h'].includes(argv[0])) {
    return { help: true };
  }
  const [command, ...rest] = argv;
  const options = { command, dryRun: command === 'dry-run' };
  const args = rest;
  options.operation = options.dryRun ? args.shift() : command;
  for (let index = 0; index < args.length; index += 1) {
    if (args[index] === '--uid') options.uid = args[++index];
    else if (args[index] === '--project') options.projectId = args[++index];
    else if (args[index] === '--help' || args[index] === '-h') {
      options.help = true;
    } else {
      throw new Error(`Unknown argument: ${args[index]}`);
    }
  }
  if (!options.projectId) {
    options.projectId = process.env.GOOGLE_CLOUD_PROJECT;
  }
  return options;
}

function usage() {
  return [
    'Usage:',
    '  node lo-authorization.js approve --uid UID --project PROJECT_ID',
    '  node lo-authorization.js revoke --uid UID --project PROJECT_ID',
    '  node lo-authorization.js inspect --uid UID --project PROJECT_ID',
    '  node lo-authorization.js migrate --uid UID --project PROJECT_ID',
    '  node lo-authorization.js dry-run <approve|revoke|migrate> --uid UID --project PROJECT_ID',
    '  node lo-authorization.js migrate-all --project PROJECT_ID',
    '  node lo-authorization.js dry-run migrate-all --project PROJECT_ID',
    '',
    'Authenticate locally first with: gcloud auth application-default login',
  ].join('\n');
}

async function inspectLO(db, uid) {
  if (!uid) throw new Error('A LO uid is required.');
  const profileSnapshot = await db.collection('users').doc(uid).get();
  const availabilitySnapshot = await db
    .collection('loAvailability')
    .doc(uid)
    .get();
  if (!profileSnapshot.exists) {
    return { uid, exists: false, errors: [`users/${uid} does not exist.`] };
  }
  const profile = profileSnapshot.data();
  let claim = null;
  if (typeof profile.id === 'string') {
    const claimSnapshot = await db
      .collection('registrationIds')
      .doc(profile.id)
      .get();
    if (claimSnapshot.exists) claim = claimSnapshot.data();
  }
  const errors = [];
  try {
    validateLORecord(uid, profile, claim);
  } catch (error) {
    errors.push(error.message);
  }
  return {
    uid,
    exists: true,
    profile: {
      role: profile.role,
      id: profile.id,
      authorized: profile.authorized,
    },
    registrationClaim: claim,
    availability: availabilitySnapshot.exists
      ? availabilitySnapshot.data()
      : null,
    validLO: errors.length === 0,
    errors,
  };
}

async function migrateAll(db, fieldValue, dryRun) {
  const profiles = await db
    .collection('users')
    .where('role', '==', LO_ROLE)
    .get();
  const results = [];
  for (const document of profiles.docs) {
    results.push(
      await updateLOAuthorization({
        db,
        fieldValue,
        uid: document.id,
        operation: 'migrate',
        dryRun,
      }),
    );
  }
  return { operation: 'migrate-all', dryRun, count: results.length, results };
}

async function main(argv = process.argv.slice(2)) {
  const options = parseArgs(argv);
  if (options.help || !options.command) {
    console.log(usage());
    return;
  }
  const allowed = [
    'approve',
    'revoke',
    'inspect',
    'migrate',
    'migrate-all',
    'dry-run',
  ];
  if (!allowed.includes(options.command)) {
    throw new Error(`Unknown command: ${options.command}\n${usage()}`);
  }
  if (!options.projectId) {
    throw new Error(
      'Specify --project or set GOOGLE_CLOUD_PROJECT to prevent targeting the wrong project.',
    );
  }

  const { applicationDefault, initializeApp } = require('firebase-admin/app');
  const { FieldValue, getFirestore } = require('firebase-admin/firestore');
  const app = initializeApp({
    credential: applicationDefault(),
    projectId: options.projectId,
  });
  const db = getFirestore(app);

  let result;
  if (options.command === 'inspect') {
    result = await inspectLO(db, options.uid);
  } else if (options.command === 'migrate-all') {
    result = await migrateAll(db, FieldValue, false);
  } else if (
    options.command === 'dry-run' &&
    options.operation === 'migrate-all'
  ) {
    result = await migrateAll(db, FieldValue, true);
  } else {
    result = await updateLOAuthorization({
      db,
      fieldValue: FieldValue,
      uid: options.uid,
      operation: options.operation,
      dryRun: options.dryRun,
    });
  }
  console.log(JSON.stringify(result, null, 2));
}

if (require.main === module) {
  main().catch((error) => {
    console.error(`LO authorization command failed: ${error.message}`);
    process.exitCode = 1;
  });
}

module.exports = {
  LO_ID_PATTERN,
  inspectLO,
  main,
  migrateAll,
  parseArgs,
  updateLOAuthorization,
  validateLORecord,
};
