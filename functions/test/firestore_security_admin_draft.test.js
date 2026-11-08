"use strict";

// Contrôles STATIQUES du projet de règles. Ils ne remplacent pas les tests
// exécutés par le véritable moteur de règles Firebase Emulator.
const {test} = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const source = fs.readFileSync(path.resolve(__dirname,
    "../local/firestore_security_admin_TEST.rules"), "utf8");

function section(name) {
  const index = source.indexOf(`match /${name}`);
  assert.ok(index >= 0, `Collection absente: ${name}`);
  return source.slice(index, source.indexOf("\n    match /", index + 1) === -1 ?
      source.length : source.indexOf("\n    match /", index + 1));
}

test("FIRESTORE TEST : aucune écriture ouverte à tous", () => {
  assert.doesNotMatch(source, /allow\s+(?:read\s*,\s*)?write\s*:\s*if\s+true/);
  assert.match(source, /match \/\{document=\*\*\} \{/);
  assert.match(source, /allow read, write: if false/);
});

test("FIRESTORE TEST : session Super Admin authentifiée et bornée", () => {
  assert.match(source, /SPHOT_SUPER_ADMIN/);
  assert.match(source, /sphotSuperAdmin/);
  assert.match(source, /sphotSaSessionExpiresAt/);
  assert.match(source, /request\.time\.toMillis\(\)/);
});

test("FIRESTORE TEST : aucune approbation cliente", () => {
  const request = section("adminRequests/{requestId}");
  assert.match(request, /allow create: if validInitialRequest/);
  assert.match(request, /allow update: if applicantCorrectionOnly/);
  assert.doesNotMatch(request, /allow update: if superAdmin\(\);/);
  assert.match(source, /resource\.data\.get\('status', ''\) in \['pending', 'rejected'\]/);
  assert.match(source, /request\.resource\.data\.get\('status', ''\) == 'pending'/);
});

test("FIRESTORE TEST : abonnements, preuves et paiements inaccessibles", () => {
  const subscriptions = section("subscriptions/{adminId}");
  assert.match(subscriptions, /ownerBillingOnly/);
  assert.doesNotMatch(subscriptions, /in\s*\[[^\]]*'active'/);
  assert.doesNotMatch(subscriptions, /in\s*\[[^\]]*'trial'/);
  assert.match(section("adminOdooReviewEvidence/{adminId}"),
      /allow read, write: if false/);
  assert.match(section("adminOdooEngagementEvidence/{adminId}"),
      /allow read, write: if false/);
  assert.match(section("adminOdooCycles/{cycleId}"),
      /allow read, write: if false/);
});

test("FIRESTORE TEST : aucune configuration de déploiement modifiée", () => {
  const config = JSON.parse(fs.readFileSync(path.resolve(__dirname,
      "../../firebase.json"), "utf8"));
  assert.ok(!config.firestore,
      "Ne pas raccorder le projet de règles au déploiement par défaut.");
});
