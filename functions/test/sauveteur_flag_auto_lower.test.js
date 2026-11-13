"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {autoLowerClosedFlags} = require("../sauveteur_flag_auto_lower");

const period = {
  label: "PÉRIODE TEST",
  startDate: new Date("2026-11-01T23:00:00.000Z"),
  endDate: new Date("2026-11-29T23:00:00.000Z"),
  startHour: "11:00",
  endHour: "19:00",
  timeZone: "Europe/Paris",
};

function fixture({now, rootPosition = "hisse", currentPosition = null} = {}) {
  const writes = [];
  const spotData = {
    territoireId: "fr-test",
    liveFlag: {flagColor: "green", flagPosition: rootPosition},
  };
  const rootRef = {kind: "root"};
  const territorySpotRef = {
    kind: "territorySpot",
    get: async () => ({data: () => ({
      nomSecours: "LONGE 09",
      periodesSurveillance: [period.label],
    })}),
    collection: () => ({doc: () => ({kind: "journal"})}),
  };
  const periodsRef = {
    kind: "periods",
    get: async () => ({
      docs: [{id: "p1", data: () => period}],
    }),
  };
  const chain = {
    collection: (name) => {
      if (name === "spots") {
        return {
          where: () => ({
            orderBy: () => ({
              limit: () => ({
                get: async () => ({
                  empty: false,
                  size: 1,
                  docs: [{id: "9", ref: rootRef, data: () => spotData}],
                }),
              }),
            }),
          }),
        };
      }
      if (name === "territoires") {
        return {doc: () => ({
          collection: (col) => {
            if (col === "spots") return {doc: () => territorySpotRef};
            if (col === "periodesSurveillance") return periodsRef;
            throw Error("Unexpected territory collection");
          },
        })};
      }
      if (name === "sauveteurOperationalAudit") {
        return {doc: () => ({kind: "audit"})};
      }
      throw Error(`Unexpected collection: ${name}`);
    },
    runTransaction: async (fn) => {
      const transaction = {
        get: async (ref) => {
          if (ref === rootRef) {
            return {data: () => ({
              liveFlag: {flagColor: "green",
                flagPosition: currentPosition || rootPosition},
            })};
          }
          return ref.get();
        },
        set: (ref, data) => writes.push({ref, data}),
      };
      return fn(transaction);
    },
  };
  const admin = {
    firestore: {
      FieldPath: {documentId: () => "id"},
      FieldValue: {serverTimestamp: () => "server-time"},
    },
  };
  return {db: chain, admin, writes, now};
}

test("affalage automatique à l'heure de fermeture : état, auteur, audit", async () => {
  const ctx = fixture({now: new Date("2026-11-13T18:00:00Z")});
  const result = await autoLowerClosedFlags(ctx.db, ctx.admin, ctx.now);
  assert.equal(result.lowered, 1);
  assert.equal(result.errors, 0);
  assert.equal(ctx.writes.length, 3);
  const values = ctx.writes.map((write) => write.data);
  assert.equal(values[0].liveFlag.flagPosition, "affale");
  assert.equal(values[1].type, "Drapeau");
  assert.equal(values[1].createdBy.role, "SYSTÈME");
  assert.equal(values[1].source, "automatic_surveillance_closure");
  assert.equal(values[2].source, "automatic_surveillance_closure");
  assert.equal(values[2].spotId, "9");
});

test("ne doit jamais affaler avant l'heure de fin", async () => {
  const ctx = fixture({now: new Date("2026-11-13T17:59:00Z")});
  const result = await autoLowerClosedFlags(ctx.db, ctx.admin, ctx.now);
  assert.equal(result.lowered, 0);
  assert.equal(ctx.writes.length, 0);
});

test("relecture transactionnelle : aucun doublon après un premier affalage",
    async () => {
      const ctx = fixture({
        now: new Date("2026-11-13T18:00:00Z"),
        currentPosition: "affale",
      });
      const result = await autoLowerClosedFlags(ctx.db, ctx.admin, ctx.now);
      assert.equal(result.lowered, 0);
      assert.equal(ctx.writes.length, 0);
    });

test("fonction planifiée distincte, sans imitation de sauveteur", () => {
  const source = fs.readFileSync(
      path.join(__dirname, "../index.js"), "utf8");
  assert.match(source, /exports\.autoLowerSauveteurFlags = onSchedule/);
  assert.match(source, /schedule: "\* \* \* \* \*"/);
  const closure = fs.readFileSync(
      path.join(__dirname, "../sauveteur_flag_auto_lower.js"), "utf8");
  assert.match(closure, /transaction\.set\(journalRef/);
  assert.match(closure, /transaction\.set\(auditRef/);
  assert.match(closure, /transaction\.set\(candidate\.ref/);
  assert.match(closure, /Ne constitue pas une constatation de manœuvre physique/);
});
