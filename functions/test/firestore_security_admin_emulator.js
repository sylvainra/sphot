"use strict";

// Smoke test réel des règles exécutées par Firebase Emulator via REST.
// Le garde-fou interdit toute cible réseau ou tout projet non DEMO.
const assert = require("node:assert/strict");
const host = process.env.FIRESTORE_EMULATOR_HOST;
const project = "demo-sphot-admin-security";

if (!host || !/^(127\.0\.0\.1|localhost):8181$/.test(host)) {
  throw new Error("FIRESTORE_EMULATOR_LOCAL_8181_REQUIRED");
}
const base = `http://${host}/v1/projects/${project}/databases/(default)/documents`;

async function read(collection) {
  const response = await fetch(`${base}/${collection}/test_security_001`);
  return {code: response.status, body: await response.text()};
}

async function create(collection) {
  const response = await fetch(`${base}/${collection}?documentId=test_security_001`, {
    method: "POST",
    headers: {"content-type": "application/json"},
    body: JSON.stringify({fields: {
      uid: {stringValue: "test_security_001"},
      status: {stringValue: "approved"},
    }}),
  });
  return {code: response.status, body: await response.text()};
}

async function main() {
  let checks = 0;
  for (const collection of ["adminRequests", "admins", "subscriptions",
    "adminOdooReviewEvidence", "adminOdooEngagementEvidence",
    "adminOdooCycles", "territoires", "settings", "advertiserRequests",
    "legalVersions/test_security_001/unknownSubcollection"]) {
    const result = await read(collection);
    assert.equal(result.code, 403,
        `${collection}: lecture anonyme interdite (reçu ${result.code})`);
    checks++;
  }
  for (const collection of ["adminRequests", "admins", "subscriptions",
    "adminOdooReviewEvidence", "adminOdooEngagementEvidence",
    "adminOdooCycles", "territoires", "settings", "test"]) {
    const result = await create(collection);
    assert.equal(result.code, 403,
        `${collection}: création anonyme interdite (reçu ${result.code})`);
    checks++;
  }
  for (const collection of ["publicSpots", "legalDocuments"]) {
    const result = await read(collection);
    assert.equal(result.code, 404,
        `${collection}: lecture publique permise, document absent`);
    checks++;
  }
  process.stdout.write(`${checks} contrôles FIRESTORE DEMO EMULATOR OK.\n`);
}

main().catch((error) => {
  process.stderr.write(`FIRESTORE DEMO EMULATOR ECHEC : ${error.message}\n`);
  process.exitCode = 1;
});
