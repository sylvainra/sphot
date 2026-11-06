// Tests avec identités simulées : Firebase Emulator DEMO UNIQUEMENT.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import {dirname, resolve} from 'node:path';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection,
  doc,
  getDoc,
  getDocs,
  setDoc,
  updateDoc,
} from 'firebase/firestore';

const projectId = 'demo-sphot-admin-security';
const host = process.env.FIRESTORE_EMULATOR_HOST;
if (!host || !/^(127\.0\.0\.1|localhost):8181$/.test(host)) {
  throw new Error('FIRESTORE_DEMO_EMULATOR_8181_REQUIRED');
}

const currentDir = dirname(fileURLToPath(import.meta.url));
const rules = readFileSync(resolve(currentDir,
    '../firestore_security_admin_TEST.rules'), 'utf8');
const requestId = 'admin_request_emulator_001';
const ownerUid = 'proconnect_owner_emulator_001';
const outsiderUid = 'proconnect_other_emulator_002';
const saUid = `sphot-super-admin-${'a'.repeat(32)}`;
const now = Date.now();
let passed = 0;

async function allowed(label, action) {
  await assertSucceeds(action);
  passed++;
  process.stdout.write(`OK   ${label}\n`);
}

async function denied(label, action) {
  await assertFails(action);
  passed++;
  process.stdout.write(`BLOQUE   ${label}\n`);
}

const env = await initializeTestEnvironment({
  projectId,
  firestore: {host: '127.0.0.1', port: 8181, rules},
});

try {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (adminContext) => {
    const db = adminContext.firestore();
    await setDoc(doc(db, 'adminRequests', requestId), {
      uid: requestId, status: 'pending',
      proConnect: {uid: ownerUid, siren: '216301234',
        siret: '21630123400012'},
      structure: {siren: '216301234', siret: '21630123400012'},
      territoire: {territoireId: 'fr_test_territoire_001'},
      profile: {email: 'owner@example.invalid'},
    });
    await setDoc(doc(db, 'admins', requestId), {
      uid: requestId, role: 'admin', accessStatus: 'pending',
    });
    await setDoc(doc(db, 'subscriptions', requestId), {
      adminUid: requestId, status: 'awaiting_configuration',
      billingContactEmail: 'owner@example.invalid',
    });
  });

  const owner = env.authenticatedContext(ownerUid).firestore();
  const outsider = env.authenticatedContext(outsiderUid).firestore();
  const saClaims = {role: 'SPHOT_SUPER_ADMIN', sphotSuperAdmin: true,
    sphotSaSessionExpiresAt: now + 60 * 60 * 1000};
  const superAdmin = env.authenticatedContext(saUid, saClaims).firestore();
  const expiredAdmin = env.authenticatedContext(saUid, {
    ...saClaims, sphotSaSessionExpiresAt: now - 1000,
  }).firestore();

  await allowed('demandeur : lecture de sa demande',
      getDoc(doc(owner, 'adminRequests', requestId)));
  await allowed('demandeur : lecture de son compte ADMIN',
      getDoc(doc(owner, 'admins', requestId)));
  await allowed('demandeur : lecture de son abonnement',
      getDoc(doc(owner, 'subscriptions', requestId)));
  await denied('autre demandeur : lecture de ce dossier',
      getDoc(doc(outsider, 'adminRequests', requestId)));
  await denied('autre demandeur : abonnement tiers',
      getDoc(doc(outsider, 'subscriptions', requestId)));
  await denied('demandeur : liste de tous les dossiers',
      getDocs(collection(owner, 'adminRequests')));
  await allowed('Super Admin authentifié : liste des dossiers',
      getDocs(collection(superAdmin, 'adminRequests')));
  await denied('session Super Admin expirée : lecture refusée',
      getDoc(doc(expiredAdmin, 'adminRequests', requestId)));

  await denied('demandeur : approbation directe interdite',
      updateDoc(doc(owner, 'adminRequests', requestId), {status: 'approved'}));
  await denied('Super Admin : approbation directe interdite',
      updateDoc(doc(superAdmin, 'adminRequests', requestId),
          {status: 'approved'}));
  await denied('demandeur : modification de son accès interdite',
      updateDoc(doc(owner, 'admins', requestId),
          {accessStatus: 'approved'}));
  await denied('demandeur : abonnement actif sans Odoo interdit',
      updateDoc(doc(owner, 'subscriptions', requestId), {status: 'active'}));
  await denied('Super Admin : abonnement actif sans Odoo interdit',
      updateDoc(doc(superAdmin, 'subscriptions', requestId),
          {status: 'active'}));
  await denied('demandeur : période essai sans décision interdite',
      updateDoc(doc(owner, 'subscriptions', requestId), {status: 'trial'}));
  await denied('demandeur : fausse preuve Super Admin interdite',
      setDoc(doc(owner, 'adminOdooReviewEvidence', requestId),
          {verifiedSuperAdminReview: true}));
  await denied('Super Admin : fausse preuve sans serveur interdite',
      setDoc(doc(superAdmin, 'adminOdooReviewEvidence', requestId),
          {verifiedSuperAdminReview: true}));

  await allowed('demandeur : changement email de facturation permis',
      updateDoc(doc(owner, 'subscriptions', requestId),
          {billingContactEmail: 'billing-new@example.invalid'}));
  const bill = await getDoc(doc(owner, 'subscriptions', requestId));
  assert.equal(bill.data()?.status, 'awaiting_configuration');

  const newRequest = 'admin_request_emulator_003';
  const registration = {
    uid: newRequest, status: 'pending',
    proConnect: {uid: ownerUid},
    profile: {email: 'owner@example.invalid'},
    trialRequest: {trialDurationDays: 8, certifyRepresentative: true,
      legalReadConfirmed: true, privacyReadConfirmed: true,
      rgpdAccepted: true},
    subscriptionPreview: {status: 'awaiting_validation'},
  };
  await allowed('demandeur : création initiale en attente',
      setDoc(doc(owner, 'adminRequests', newRequest), registration));
  await denied('demandeur : création directement approuvée interdite',
      setDoc(doc(owner, 'adminRequests', 'admin_request_emulator_004'),
          {...registration, uid: 'admin_request_emulator_004',
            status: 'approved'}));
  await denied('demandeur : modification identité ProConnect interdite',
      updateDoc(doc(owner, 'adminRequests', requestId),
          {'proConnect.uid': outsiderUid}));

  await allowed('Super Admin : rejet administratif permis',
      updateDoc(doc(superAdmin, 'adminRequests', requestId),
          {status: 'rejected'}));
  await allowed('demandeur : retour en attente permis',
      updateDoc(doc(owner, 'adminRequests', requestId),
          {status: 'pending'}));
  await denied('demandeur : faux statut de suivi administratif interdit',
      updateDoc(doc(owner, 'adminRequests', requestId),
          {'administrativeTracking.status': 'approved'}));

  process.stdout.write(`\n${passed} TESTS AUTHENTIFIES FIRESTORE DEMO OK.\n`);
} finally {
  await env.cleanup();
}
