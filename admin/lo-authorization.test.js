'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  parseArgs,
  updateLOAuthorization,
  validateLORecord,
} = require('./lo-authorization');

const uid = 'lo-user-uid';
const profile = {
  uid,
  role: 'Liquidity Officer',
  id: 'S0123456',
  username: 'Officer One',
  authorized: false,
};
const claim = { uid, role: 'Liquidity Officer' };
const originalCreatedAt = { toDate: () => new Date(0) };

function makeFakeFirestore({ existingAvailability } = {}) {
  const data = {
    [`users/${uid}`]: profile,
    [`registrationIds/${profile.id}`]: claim,
    ...(existingAvailability
      ? { [`loAvailability/${uid}`]: existingAvailability }
      : {}),
  };
  const writes = [];
  const db = {
    collection(name) {
      return {
        doc(id) {
          return { path: `${name}/${id}` };
        },
      };
    },
    async runTransaction(callback) {
      const staged = [];
      const transaction = {
        async get(reference) {
          const value = data[reference.path];
          return {
            exists: value !== undefined,
            data: () => value,
          };
        },
        set(reference, value, options) {
          staged.push({ path: reference.path, value, options });
        },
      };
      const result = await callback(transaction);
      writes.push(...staged);
      return result;
    },
  };
  return { db, data, writes };
}

const fieldValue = { serverTimestamp: () => 'server timestamp' };

test('approval atomically enables profile and creates protected projection', async () => {
  const { db, writes } = makeFakeFirestore();
  const result = await updateLOAuthorization({
    db,
    fieldValue,
    uid,
    operation: 'approve',
  });

  assert.equal(result.authorized, true);
  assert.equal(writes.length, 2);
  assert.deepEqual(
    writes.find((write) => write.path === `users/${uid}`).value,
    { authorized: true, updatedAt: 'server timestamp' },
  );
  assert.deepEqual(
    writes.find((write) => write.path === `loAvailability/${uid}`).value,
    {
      uid,
      role: 'Liquidity Officer',
      name: 'Officer One',
      id: 'S0123456',
      idValid: true,
      available: false,
      authorized: true,
      createdAt: 'server timestamp',
      updatedAt: 'server timestamp',
    },
  );
});

test('revocation disables both profile and availability projection', async () => {
  const { db, writes } = makeFakeFirestore({
    existingAvailability: { createdAt: originalCreatedAt },
  });
  await updateLOAuthorization({
    db,
    fieldValue,
    uid,
    operation: 'revoke',
  });

  assert.equal(writes.length, 2);
  const projection = writes.find(
    (write) => write.path === `loAvailability/${uid}`,
  ).value;
  assert.equal(projection.authorized, false);
  assert.equal(projection.available, false);
  assert.equal(projection.createdAt, originalCreatedAt);
});

test('migration preserves authoritative authorization and forces unavailable', async () => {
  const { db, writes } = makeFakeFirestore({
    existingAvailability: {
      createdAt: originalCreatedAt,
      available: true,
    },
  });
  await updateLOAuthorization({
    db,
    fieldValue,
    uid,
    operation: 'migrate',
  });

  assert.equal(writes.length, 1);
  const projection = writes[0].value;
  assert.equal(projection.authorized, false);
  assert.equal(projection.available, false);
  assert.equal(projection.createdAt, originalCreatedAt);
});

test('dry-run validates but performs no writes', async () => {
  const { db, writes } = makeFakeFirestore();
  const result = await updateLOAuthorization({
    db,
    fieldValue,
    uid,
    operation: 'approve',
    dryRun: true,
  });

  assert.equal(result.dryRun, true);
  assert.equal(result.writes, 0);
  assert.equal(writes.length, 0);
});

test('rejects invalid profile identity and mismatched claim', () => {
  assert.throws(
    () => validateLORecord(uid, { ...profile, id: 'LO123456' }, claim),
    /not a valid LO registration ID/,
  );
  assert.throws(
    () => validateLORecord(uid, profile, { ...claim, uid: 'someone-else' }),
    /does not claim this LO profile/,
  );
  assert.throws(
    () => validateLORecord(uid, { ...profile, uid: 'someone-else' }, claim),
    /mismatched uid/,
  );
});

test('CLI supports help and explicitly targets a project', () => {
  assert.deepEqual(parseArgs(['--help']), { help: true });
  assert.deepEqual(
    parseArgs(['approve', '--uid', uid, '--project', 'altrafloat-gen-z']),
    {
      command: 'approve',
      dryRun: false,
      operation: 'approve',
      uid,
      projectId: 'altrafloat-gen-z',
    },
  );
});
