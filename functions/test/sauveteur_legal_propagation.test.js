"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const legalDocumentVersions = require("../legal_document_versions");

// Exécute les fonctions EXACTES présentes dans functions/index.js sans
// initialiser Firebase Admin ni déployer les fonctions métier.
const source = fs.readFileSync(
    path.join(__dirname, "../index.js"), "utf8");
function extract(name, isAsync = false) {
  const declaration = (isAsync ? "async " : "") + "function " + name + "(";
  const start = source.indexOf(declaration);
  assert.ok(start >= 0, "fonction attendue absente : " + name);
  const end = source.indexOf("\n}\n", start);
  assert.ok(end > start, "fin de fonction introuvable : " + name);
  return source.slice(start, end + 2);
}

function fixture() {
  const documents = {
    sauveteurCgu: {published: true, testOnly: false, version: "1.5",
      revision: 1, chapters: Array.from({length: 8}, (_, index) => ({
        id: String(index + 1).padStart(2, "0"), content: "CGU", title: "Article",
      }))},
    sauveteurCharter: {published: true, testOnly: false, version: "1.4",
      revision: 1, chapters: Array.from({length: 7}, (_, index) => ({
        id: String(index + 1).padStart(2, "0"), content: "Charte", title: "Rubrique",
      }))},
    privacyPolicy: {published: true, version: "1.2", revision: 0},
    rgpdNotice: {published: true, version: "1.3", revision: 0},
  };
  const admin = {firestore: () => ({
    collection: () => ({doc: (id) => ({get: async () => ({
      exists: Object.hasOwn(documents, id),
      data: () => documents[id],
    })})}),
  })};
  const code = extract("activeSauveteurDocumentVersions", true) + "\n" +
      extract("sauveteurLegalAcceptanceIsCurrent") + "\n" +
      "({activeSauveteurDocumentVersions, sauveteurLegalAcceptanceIsCurrent});";
  const funcs = vm.runInNewContext(code, {
    admin, legalDocumentVersions,
    SAUVETEUR_LEGAL_ACCEPTANCE_REVISION: "3",
  });
  const account = {
    legalAcceptance: {
      accepted: true, revision: "3",
      documents: {sauveteurCgu: true, sauveteurCharter: true,
        privacy: true, rgpd: true},
      documentVersions: {},
      operationalRules: {
        publicOperationalDiffusionAcknowledged: true,
        institutionalReadAcknowledged: true,
        personalAccountUseAccepted: true,
        sphotTransmissionRoleAcknowledged: true,
        professionalDecisionResponsibilityAccepted: true,
      },
    },
  };
  return {documents, funcs, account};
}

test("raccordement session : getSauveteurSessionState utilise les versions individuelles", () => {
  const begin = source.indexOf("exports.getSauveteurSessionState =");
  const end = source.indexOf("exports.acceptSauveteurLegalTerms =", begin);
  assert.ok(begin >= 0 && end > begin);
  const route = source.slice(begin, end);
  assert.match(route, /legalPack: activeLegalPack/);
  assert.match(route, /legalAcceptanceCurrent/);
  assert.match(route, /legalAcceptanceRequired = !legalAcceptanceCurrent/);
  assert.doesNotMatch(route, /await activeLegalPackInfo\(\)/);
});

test("SAUVETEUR : chaque publication CGU ou Charte oblige la reacceptation", async () => {
  const f = fixture();
  const current = await f.funcs.activeSauveteurDocumentVersions("1.7");
  assert.equal(current.sauveteurCgu, "1.5:r1");
  assert.equal(current.sauveteurCharter, "1.4:r1");
  f.account.legalAcceptance.documentVersions = {...current};

  const accepted = (versions) =>
    f.funcs.sauveteurLegalAcceptanceIsCurrent(f.account,
        {version: "1.7", documentVersions: versions});
  assert.equal(accepted(current), true);

  // Modifier uniquement les CGU d'un autre acteur ne doit rien changer.
  assert.equal(accepted({...current, adminCgu: "1.8:r1"}), false);
  // Les vrais snapshots sauveteurs ne contiennent PAS adminCgu.
  assert.equal(accepted(await f.funcs.activeSauveteurDocumentVersions("1.8")),
      true);

  // Un brouillon de Charte ne change pas le document actuellement publié.
  const draft = {revision: 2, status: "draft"};
  assert.equal(draft.status, "draft");
  assert.equal(accepted(await f.funcs.activeSauveteurDocumentVersions("1.8")),
      true);

  // Publication de la seule Charte : la version des CGU reste inchangée.
  f.documents.sauveteurCharter.revision = 2;
  const next = await f.funcs.activeSauveteurDocumentVersions("1.8");
  assert.equal(next.sauveteurCgu, current.sauveteurCgu);
  assert.equal(next.sauveteurCharter, "1.4:r2");
  assert.equal(accepted(next), false);
  f.account.legalAcceptance.documentVersions = {...next};
  assert.equal(accepted(next), true);

  // Publication des seules CGU : nouvelle réacceptation sans perdre Charte.
  f.documents.sauveteurCgu.revision = 2;
  const nextCgu = await f.funcs.activeSauveteurDocumentVersions("1.9");
  assert.equal(nextCgu.sauveteurCharter, next.sauveteurCharter);
  assert.equal(accepted(nextCgu), false);
  f.account.legalAcceptance.documentVersions = {...nextCgu};
  assert.equal(accepted(nextCgu), true);
});

test("SAUVETEUR : une Charte non publiée ne peut pas être imposée", async () => {
  const f = fixture();
  f.documents.sauveteurCharter.published = false;
  const versions = await f.funcs.activeSauveteurDocumentVersions("1.7");
  assert.equal(versions, null);
  assert.equal(f.funcs.sauveteurLegalAcceptanceIsCurrent(f.account,
      {version: "1.7", documentVersions: null}), false);
});
