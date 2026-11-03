# Security Review Summary

**Reviewed:** 2026-10-08  
**Scope:** `firestore.rules`, `lib/main.dart`, `admin/lo-authorization.js`, `admin/lo-authorization.test.js`, and `admin/package.json`

## Summary

No exploitable vulnerability was identified in the reviewed authorization rules, Flutter availability query, or Admin SDK authorization workflow. No files were changed as part of the review itself, no tests or `npm audit` were run, and no rules were deployed or Firestore commands executed.

## Findings

- `loAvailability` reads and lists for Agents are restricted by the projection predicate: `available == true`, `role == 'Liquidity Officer'`, `authorized == true`, and `idValid == true`. The owner-LO `get` permission is limited to the LO's own document. LOs have no list permission for this collection.
- LO client updates preserve `uid`, `role`, `id`, `idValid`, `authorized`, and `createdAt`; only `name`, `available`, and `updatedAt` may change.
- The Agent Flutter query applies all four projection filters.
- The Admin SDK script validates the LO UID/profile consistency, role, LO ID format, username, authorization field type, and matching registration claim UID and role before approval/revocation/migration. It uses a Firestore transaction for the profile and availability writes.
- The ID checks validate format and claim consistency, not real-world ID authenticity. This is an intentional manual administrative verification requirement, not a code defect in this architecture.
- Admin SDK credentials are used by the local Node.js admin script via Application Default Credentials. The reviewed Flutter code uses the Firebase client SDK; no Admin SDK credential bundling was found in the reviewed files.

## Migration impact

`migrate-all` selects every `users` document whose role is exactly `Liquidity Officer` and processes profiles sequentially. For each valid profile and matching registration claim, it replaces `loAvailability/{uid}` with the validated projection: the profile UID, LO role, trimmed username, ID, `idValid: true`, `available: false`, the existing profile `authorized` value, `createdAt` preserved only if it is a Firestore timestamp (otherwise a server timestamp), and a new server-timestamp `updatedAt`. It does not update the profile's authorization. Existing extra fields in each replaced availability document are removed. Stale availability documents without a matching LO profile are not selected or deleted. Since processing is sequential, earlier writes can complete before a later invalid profile causes an error.

## Dependency audit status

The local `npm audit` warning could not be verified: no audit report was available, and `npm audit` was not run. Dependency advisory status therefore remains unknown; deployment readiness with respect to dependency advisories was not assessed.

## Deployment status

This document records a read-only review. No deployment, approval, revocation, migration, or live Firestore operation was performed.
