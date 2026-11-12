"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const Module = require("node:module");

function loadExport() {
  const original = Module._load;
  let registeredOptions;
  let initialized = 0;
  let validated = 0;
  Module._load = function(request, parent, main) {
    if (request === "firebase-admin/app") return {initializeApp: () => {initialized++; return {name: "sphot-legal-test"};}};
    if (request === "firebase-admin") throw new Error("Legacy Firebase Admin SDK prohibited");
    if (request === "firebase-admin/auth") return {
      getAuth: (app) => {
        assert.equal(app.name, "sphot-legal-test");
        return {verifyIdToken: async () => {validated++; return {};}};
      },
    };
    if (request === "firebase-admin/firestore") return {
      getFirestore: (app) => {
        assert.equal(app.name, "sphot-legal-test");
        throw new Error("No Firestore read expected for denied requests");
      },
      FieldValue: {serverTimestamp: () => "SERVER_TIMESTAMP"},
    };
    if (request === "firebase-functions/v2/https") return {
      onRequest: (options, handler) => {registeredOptions = options; return handler;},
    };
    return original.apply(this, arguments);
  };
  try {
    delete require.cache[require.resolve("../index")];
    const exports = require("../index");
    return {exports, registeredOptions, initialized, validated: () => validated};
  } finally {Module._load = original;}
}
function mockResponse() {
  const result = {statusCode: 200, body: null, headers: {}};
  result.set = (key, val) => {result.headers[key] = val; return result;};
  result.status = (val) => {result.statusCode = val; return result;};
  result.json = (val) => {result.body = val; return result;};
  return result;
}
test("paquet juridique : deux fonctions uniquement, initialise Firebase une fois", () => {
  const loaded = loadExport();
  assert.deepEqual(Object.keys(loaded.exports).sort(), ["manageSphotLegalDocumentEditing", "manageSphotInitialLegalPack"].sort());
  assert.equal(loaded.initialized, 1);
  assert.equal(loaded.registeredOptions.region, "us-central1");
});
test("HTTP non authentifie refuse, aucun acces Firestore requis", async () => {
  const loaded = loadExport();
  const res = mockResponse();
  await loaded.exports.manageSphotLegalDocumentEditing({method: "POST",get:()=>"",body:{action:"status", documentId:"cgu"}},res);
  assert.equal(res.statusCode,401);
  assert.equal(loaded.validated(),0);
});
test("jeton sans droits Super Admin refuse", async () => {
  const loaded = loadExport();
  const res = mockResponse();
  await loaded.exports.manageSphotLegalDocumentEditing({method:"POST", get:()=>"Bearer token-sans-droits",body:{action:"status",documentId:"cgu"}},res);
  assert.equal(res.statusCode,403);
  assert.equal(loaded.validated(),1);
});
test("publication individuelle manuelle activee sans variable d'environnement", () => {
  const editor = require("../legal_document_editor");
  const fs = require("node:fs");
  const source = fs.readFileSync(require.resolve("../legal_document_editor"),"utf8");
  assert.ok(source.includes("allowPublish: true /* publication individuelle explicite uniquement */"));
  assert.ok(!source.includes("allowPublish: process.env."));
  assert.deepEqual(Object.keys(editor.SPECIFICATIONS).sort(),[
    "cgu","adminCgu","advertiserCgu","adminCgv","advertiserCgv",
    "sauveteurCgu","sauveteurCharter","rgpdNotice","privacyPolicy"].sort());
});
