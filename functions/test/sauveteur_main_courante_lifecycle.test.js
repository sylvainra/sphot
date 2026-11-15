"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {
  parisCivilYear,
  mainCouranteLifecycle,
  mainCouranteReadBounds,
  purgeExpiredMainCourante,
} = require("../sauveteur_main_courante_lifecycle");

const source = fs.readFileSync(path.join(__dirname, "../index.js"), "utf8");
const autoLower = fs.readFileSync(
    path.join(__dirname, "../sauveteur_flag_auto_lower.js"), "utf8");

const period = (id, start, end) => ({
  id,
  label: "SAISON " + id,
  startDate: new Date(start),
  endDate: new Date(end),
});

const assigned = [{periodesSurveillance: ["2026"]}];
const periods = [
  period("2026", "2026-06-01T22:00:00Z", "2026-08-31T22:00:00Z"),
];

test("dernière journée de surveillance entièrement modifiable, lendemain fermé",
    () => {
      const before = mainCouranteLifecycle(
          {}, assigned, periods, new Date("2026-08-31T21:59:59Z"));
      const lastSecond = mainCouranteLifecycle(
          {}, assigned, periods, new Date("2026-08-31T21:59:59.999Z"));
      const closed = mainCouranteLifecycle(
          {}, assigned, periods, new Date("2026-08-31T22:00:00Z"));
      assert.equal(before.writable, true);
      assert.equal(lastSecond.writable, true);
      assert.equal(closed.writable, false);
      assert.equal(closed.closed, true);
      assert.equal(closed.lastSurveillanceDay, 20260831);
    });

test("les autres périodes non affectées ne prolongent pas la saison", () => {
  const extra = period(
      "other", "2026-05-01T22:00:00Z", "2026-12-31T23:00:00Z");
  const result = mainCouranteLifecycle(
      {}, assigned, [...periods, extra], new Date("2026-11-15T16:00:00Z"));
  assert.equal(result.closed, true);
  assert.equal(result.writable, false);
});

test("plusieurs périodes du même poste utilisent la dernière date incluse",
    () => {
      const both = [
        {periodesSurveillance: ["2026", "automne"]},
      ];
      const autumn = period(
          "automne", "2026-10-01T22:00:00Z", "2026-11-29T23:00:00Z");
      const active = mainCouranteLifecycle(
          {}, both, [...periods, autumn], new Date("2026-11-30T20:00:00Z"));
      const closed = mainCouranteLifecycle(
          {}, both, [...periods, autumn], new Date("2026-11-30T23:00:00Z"));
      assert.equal(active.writable, true);
      assert.equal(closed.writable, false);
      assert.equal(closed.lastSurveillanceDay, 20261130);
    });

test("sans période affectée, le serveur ne crée jamais de nouvelles entrées",
    () => {
      const result = mainCouranteLifecycle(
          {}, [], periods, new Date("2026-07-10T12:00:00Z"));
      assert.equal(result.writable, false);
    });

test("période 2027 ne réouvre pas une main courante de 2026", () => {
  const next = period("2027",
      "2027-06-01T22:00:00Z", "2027-08-31T22:00:00Z");
  const result = mainCouranteLifecycle(
      {}, [{periodesSurveillance: ["2026", "2027"]}],
      [...periods, next], new Date("2026-11-15T12:00:00Z"));
  assert.equal(result.writable, false);
  assert.equal(result.closed, true);
});

test("calendrier Paris: année nouvelle à 23h00 UTC le 31 décembre", () => {
  assert.equal(
      parisCivilYear(new Date("2026-12-31T22:59:59Z")).year, 2026);
  assert.equal(
      parisCivilYear(new Date("2026-12-31T23:00:00Z")).year, 2027);
  const now = new Date("2026-12-31T23:00:00Z");
  const bounds = mainCouranteReadBounds({}, now);
  assert.equal(bounds.from,
      new Date("2026-12-31T23:00:00Z").getTime());
  assert.equal(bounds.until,
      new Date("2027-12-31T23:00:00Z").getTime());
});

test("lecture de l'année précédente inaccessible avant la purge", () => {
  const jan1 = new Date("2026-12-31T23:00:00Z");
  const previous = mainCouranteReadBounds({
    dayStartMillis: new Date("2026-07-01T00:00:00Z").getTime(),
    dayEndMillis: new Date("2026-07-02T00:00:00Z").getTime(),
  }, jan1);
  assert.equal(previous.empty, true);
  const sameYear = mainCouranteReadBounds({
    dayStartMillis: new Date("2027-07-01T00:00:00Z").getTime(),
    dayEndMillis: new Date("2027-07-02T00:00:00Z").getTime(),
  }, jan1);
  assert.equal(sameYear.empty, false);
});

test("routes de lecture: consultation OFF, écriture bloquée et année bornée",
    () => {
      const read = source.split("exports.getSauveteurMainCourante =")[1]
          .split("exports.")[0];
      const stats = source.split("exports.getSauveteurStats =")[1]
          .split("exports.")[0];
      const institutional = source.split(
          "exports.getInstitutionalMainCourante =")[1].split("exports.")[0];
      assert.match(read, /context\.assignedSpotIds\.includes\(spotId\)/);
      assert.doesNotMatch(read, /context\.sphotMode !== "ON"/);
      assert.match(read, /mainCouranteReadBounds/);
      assert.match(stats, /mainCouranteReadBounds/);
      assert.match(institutional, /mainCouranteReadBounds/);
      for (const name of [
        "recordSauveteurMaterialVerification",
        "addSauveteurMainCouranteEntry",
        "updateSauveteurMainCouranteEntry",
        "deleteSauveteurMainCouranteEntry",
      ]) {
        const handler = source.split("exports." + name + " =")[1]
            .split("exports.")[0];
        assert.match(handler, /loadMainCouranteLifecycle/);
        assert.match(handler, /main_courante_closed/);
      }
      assert.match(autoLower, /if \(journalOpen\) transaction\.set/);
      assert.match(source, /exports\.purgeExpiredSauveteurMainCourante/);
    });

function fakeCollection(initial, name = "collection") {
  const rows = initial.map((data, i) => ({
    data: () => data,
    id: name + "-" + i,
    ref: {name, i, removed: false},
  }));
  return {
    rows,
    where(field, op, cutoff) {
      assert.equal(op, "<");
      return {
        limit(size) {
          return {
            async get() {
              const matches = rows.filter((row) =>
                !row.ref.removed && row.data()[field] < cutoff);
              return {
                docs: matches.slice(0, size),
                empty: matches.length === 0,
              };
            },
          };
        },
      };
    },
  };
}

test("la purge retire récits, corrections et vues expirées, jamais 2027",
    async () => {
      const old = new Date("2026-08-01T00:00:00Z");
      const current = new Date("2027-03-01T00:00:00Z");
      const entries = fakeCollection([
        {occurredAt: old}, {occurredAt: current},
      ], "journal");
      const edits = fakeCollection([
        {createdAt: old}, {createdAt: current},
      ], "edit");
      const views = fakeCollection([
        {viewedAt: old}, {viewedAt: current},
      ], "view");
      const stationRef = {
        collection(name) {
          assert.equal(name, "mainCourante");
          return entries;
        },
      };
      const territory = {
        collection(name) {
          assert.equal(name, "spots");
          return {listDocuments: async () => [stationRef]};
        },
      };
      const db = {
        collection(name) {
          if (name === "territoires") {
            return {listDocuments: async () => [territory]};
          }
          if (name === "mainCouranteAuditLogs") return edits;
          if (name === "mainCouranteAccessLogs") return views;
          throw new Error("unexpected collection: " + name);
        },
        batch() {
          const pending = [];
          return {
            delete(ref) { pending.push(ref); },
            async commit() {
              for (const ref of pending) ref.removed = true;
            },
          };
        },
      };
      const admin = {
        firestore: {Timestamp: {fromDate: (date) => date}},
      };
      const result = await purgeExpiredMainCourante(
          db, admin, new Date("2026-12-31T23:00:00Z"));
      assert.deepEqual(result, {
        year: 2027, entries: 1, edits: 1, views: 1,
      });
      for (const collection of [entries, edits, views]) {
        assert.deepEqual(
            collection.rows.map((row) => row.ref.removed), [true, false]);
      }
    });
