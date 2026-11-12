"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {snapshot, matchesRequested} = require("../legal_document_versions");

test("versions propres et historique non numéroté", () => {
  const versions = snapshot({
    cgu: {version: "1.1", revision: 0},
    privacyPolicy: {version: "1.0"},
    rgpdNotice: {version: "1.2", revision: 1},
  }, "1.2");
  assert.deepEqual(versions, {
    cgu: "1.1:r0",
    privacyPolicy: "1.0:historique",
    rgpdNotice: "1.2:r1",
  });
  assert.equal(matchesRequested(versions, versions), true);
  assert.equal(matchesRequested({...versions, rgpdNotice: "1.0:historique"},
      versions), false);
  assert.equal(matchesRequested(null, versions), true);
  assert.equal(matchesRequested({}, versions), false);
});

test("versions CGU SAUVETEUR et Charte distinctes, obligatoires", () => {
  const versions = snapshot({
    cgu: {version: "2.0", revision: 0},
    charter: {version: "2.1", revision: 3},
    privacyPolicy: {version: "1.0", revision: 1},
    rgpdNotice: {version: "1.2", revision: 0},
  }, "2.1", {cguId: "sauveteurCgu", charterId: "sauveteurCharter"});
  assert.equal(versions.sauveteurCgu, "2.0:r0");
  assert.equal(versions.sauveteurCharter, "2.1:r3");
  assert.equal(versions.cgu, undefined);
  assert.equal(matchesRequested(null, versions, {required: true}), false);
  assert.equal(matchesRequested({sauveteurCgu: "2.0:r0"}, versions,
      {required: true}), false);
  assert.equal(matchesRequested(versions, versions, {required: true}), true);
});
