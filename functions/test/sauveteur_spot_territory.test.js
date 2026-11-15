"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {attachOperationalSpotTerritory} =
    require("../sauveteur_spot_territory");

/**
 * @param {?Object} initial Root spot data or null when absent.
 * @return {Object} Fake transactional Firestore.
 */
function fixture(initial) {
  const writes = [];
  let root = initial === null ? null : {...initial};
  const reference = {id: "9"};
  const db = {
    collection: (name) => {
      assert.equal(name, "spots");
      return {doc: (id) => {
        assert.equal(id, "9");
        return reference;
      }};
    },
    runTransaction: (fn) => fn({
      get: async (ref) => {
        assert.equal(ref, reference);
        return {exists: root !== null, data: () => root};
      },
      set: (ref, changes, options) => {
        assert.equal(ref, reference);
        assert.deepEqual(options, {merge: true});
        writes.push(changes);
        root = {...root, ...changes};
      },
    }),
  };
  return {db, writes, root: () => root};
}

test("Admin edit attaches territory, preserving every live flag", async () => {
  const ctx = fixture({
    statutBaignade: "Baignade autorisee",
    liveFlag: {flagColor: "red", flagPosition: "hisse"},
  });
  const result = await attachOperationalSpotTerritory(
      ctx.db, "france-pays-de-la-loire", "9");
  assert.equal(result, "associated");
  assert.deepEqual(ctx.writes, [{territoireId: "france-pays-de-la-loire"}]);
  assert.deepEqual(ctx.root().liveFlag,
      {flagColor: "red", flagPosition: "hisse"});
  assert.equal(ctx.root().statutBaignade, "Baignade autorisee");
});

test("Already linked spot stays unchanged", async () => {
  const ctx = fixture({territoireId: "fr-test", liveFlag: {}});
  const result = await attachOperationalSpotTerritory(
      ctx.db, "fr-test", "9");
  assert.equal(result, "already_associated");
  assert.equal(ctx.writes.length, 0);
});

test("Refuses a root ID already owned by another territory", async () => {
  const ctx = fixture({territoireId: "fr-other", liveFlag: {}});
  const result = await attachOperationalSpotTerritory(
      ctx.db, "fr-test", "9");
  assert.equal(result, "territory_conflict");
  assert.equal(ctx.writes.length, 0);
  assert.equal(ctx.root().territoireId, "fr-other");
});

test("Admin creation without an operational root creates nothing", async () => {
  const ctx = fixture(null);
  const result = await attachOperationalSpotTerritory(
      ctx.db, "fr-test", "9");
  assert.equal(result, "operational_spot_absent");
  assert.equal(ctx.writes.length, 0);
});

test("Refuses empty territory and spot identifiers", async () => {
  const ctx = fixture({});
  await assert.rejects(
      attachOperationalSpotTerritory(ctx.db, "", "9"),
      /missing_spot_territory_identity/);
  await assert.rejects(
      attachOperationalSpotTerritory(ctx.db, "fr-test", ""),
      /missing_spot_territory_identity/);
  assert.equal(ctx.writes.length, 0);
});

test("Server wires ordinary Admin updates and trusted Sauveteur writes", () => {
  const source = fs.readFileSync(
      path.join(__dirname, "../index.js"), "utf8");
  const begin = source.indexOf("exports.syncPublicSpotOnWrite =");
  const end = source.indexOf("exports.syncPublicSpotLiveStateOnWrite =", begin);
  assert.ok(begin >= 0 && end > begin);
  assert.match(source.slice(begin, end), /attachOperationalSpotTerritory/);
  assert.match(source,
      /\.\.\.sanitizedChanges,\s*territoireId: context\.territoireId,/);
  assert.match(source, /operationalTerritoryId !== context\.territoireId/);
});
