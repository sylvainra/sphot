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
