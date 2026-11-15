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

/**
 * Simule une lecture du poste puis son affalage atomique.
 * @param {Object} options Options.
 * @return {Object} Base factice et écritures enregistrées.
 */
function fixture({
  now, rootPosition = "hisse", currentPosition = null,
  purple = false, windsock = false, prepared = null,
  assignedPeriodIds = ["p1"],
  assignedPeriodLists = null, periodData = period, status = null,
} = {}) {
  const writes = [];
  const spotData = {
    territoireId: "fr-test",
    statutBaignade: status,
    liveFlag: {
      flagColor: "green", flagPosition: rootPosition,
      purpleFlagActive: purple, windsockActive: windsock,
    },
    preparedFlag: prepared ? {...prepared, pending: true} : null,
  };
  const rootRef = {kind: "root"};
  const assignedRef = {
    kind: "assignedSauveteurs",
    get: async () => ({
      docs: (assignedPeriodLists || [assignedPeriodIds])
          .map((ids, index) => ({
            id: `sauveteur${index}`,
            data: () => ({periodesSurveillance: ids}),
          })),
    }),
  };
  const territorySpotRef = {
    kind: "territorySpot",
    get: async () => ({data: () => ({
      nomSecours: "LONGE 09",
      periodesSurveillance: ["ANCIENNE PÉRIODE PÉRIMÉE"],
    })}),
    collection: (name) => name === "sauveteursAffectes" ?
      assignedRef : {doc: () => ({kind: "journal"})},
  };
  const periodsRef = {
    kind: "periods",
    get: async () => ({
      docs: [{id: "p1", data: () => periodData}],
    }),
  };
  const chain = {
    collection: (name) => {
      if (name === "spots") {
        return {
          where: (field, operator, value) => ({
            orderBy: () => ({
              limit: () => ({
                get: async () => {
                  const key = field.split(".").pop();
                  const state = field.startsWith("preparedFlag.") ?
                    spotData.preparedFlag : spotData.liveFlag;
                  const current = field === "statutBaignade" ?
                    spotData.statutBaignade : state && state[key];
                  const found = operator === "in" ?
                    value.includes(current) : current === value;
                  return {
                    empty: !found,
                    size: found ? 1 : 0,
                    docs: found ?
                      [{id: "9", ref: rootRef, data: () => spotData}] : [],
                  };
                },
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
              liveFlag: {
                flagColor: "green",
                flagPosition: currentPosition || rootPosition,
                purpleFlagActive: purple, windsockActive: windsock,
              },
              preparedFlag: prepared ? {...prepared, pending: true} : null,
              statutBaignade: status,
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
      FieldValue: {
        serverTimestamp: () => "server-time",
        delete: () => "deleted",
      },
    },
  };
  return {db: chain, admin, writes, now};
}

test("aucune préparation publiée hors horaires", async () => {
  const ctx = fixture({
    now: new Date("2026-11-14T09:59:00Z"), rootPosition: "affale",
    prepared: {flagColor: "yellow"},
  });
  const result = await autoLowerClosedFlags(ctx.db, ctx.admin, ctx.now);
  assert.equal(result.lowered, 0);
  assert.equal(result.published, 0);
  assert.equal(ctx.writes.length, 0);
});

test("affalage automatique à la fermeture : état, auteur, audit", async () => {
  const ctx = fixture({now: new Date("2026-11-13T18:00:00Z")});
  const result = await autoLowerClosedFlags(ctx.db, ctx.admin, ctx.now);
  assert.equal(result.lowered, 1);
  assert.equal(result.errors, 0);
  assert.equal(ctx.writes.length, 3);
  const values = ctx.writes.map((write) => write.data);
  assert.equal(values[0].liveFlag.flagPosition, "affale");
  assert.equal(values[0].statutBaignade, "Baignade non surveillée");
  assert.match(values[1].description, /^AFFALÉS : VERT$/);
  assert.equal(values[1].actionTaken, "");
  assert.equal(values[0].liveFlag.purpleFlagActive, false);
  assert.equal(values[0].liveFlag.windsockActive, false);
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
        status: "Baignade non surveillée",
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
  assert.match(closure, /mastAtClosure = describeFlagMast\(live, true\)/);
});

test("fermeture : coupe violet et manche à air avec drapeau affalé",
    async () => {
      const ctx = fixture({
        now: new Date("2026-11-13T18:00:00Z"),
        rootPosition: "affale", purple: true, windsock: true,
      });
      const result = await autoLowerClosedFlags(ctx.db, ctx.admin, ctx.now);
      assert.equal(result.errors, 0);
      assert.equal(result.lowered, 1);
      assert.equal(result.inspected, 1);
      assert.equal(ctx.writes[0].data.liveFlag.flagPosition, "affale");
      assert.equal(ctx.writes[0].data.liveFlag.purpleFlagActive, false);
      assert.equal(ctx.writes[0].data.liveFlag.windsockActive, false);
      assert.match(
          ctx.writes[1].data.description,
          /^AFFALÉS : VERT, VIOLET, MANCHE À AIR$/);
      assert.match(ctx.writes[1].data.description, /MANCHE À AIR/);
    });

test("ne désactive pas les signaux complémentaires avant la fermeture",
    async () => {
      const ctx = fixture({
        now: new Date("2026-11-13T17:59:00Z"),
        rootPosition: "affale", windsock: true,
      });
      const result = await autoLowerClosedFlags(ctx.db, ctx.admin, ctx.now);
      assert.equal(result.lowered, 0);
      assert.equal(ctx.writes.length, 0);
    });

test("une fermeture transactionnelle utilise le même instant de contrôle",
    () => {
      const source = fs.readFileSync(
          path.join(__dirname, "../sauveteur_flag_auto_lower.js"), "utf8");
      assert.match(source, /freshAssigned\.docs\.map[\s\S]*?\n\s*now,/);
    });

test("périodes du sauveteur : le poste reste fermé sans affectation",
    async () => {
      const ctx = fixture({
        now: new Date("2026-11-14T15:56:14.536Z"),
        assignedPeriodIds: [],
      });
      const result = await autoLowerClosedFlags(ctx.db, ctx.admin, ctx.now);
      assert.equal(result.lowered, 1);
      assert.equal(result.errors, 0);
    });
test("automatisme : respecte les deux plages et la pause du midi",
    async () => {
      const twoSlots = {...period, startHour: "09:00", endHour: "12:00",
        secondStartHour: "14:00", secondEndHour: "18:00"};
      for (const [instant, shouldLower] of [
        ["2026-11-14T10:59:00Z", false],
        ["2026-11-14T11:00:00Z", true],
        ["2026-11-14T13:00:00Z", false],
        ["2026-11-14T17:00:00Z", true],
      ]) {
        const ctx = fixture({now: new Date(instant), periodData: twoSlots});
        const result = await autoLowerClosedFlags(ctx.db, ctx.admin, ctx.now);
        assert.equal(result.errors, 0);
        assert.equal(result.lowered, shouldLower ? 1 : 0, instant);
      }
    });

test("automatisme : plusieurs sauveteurs, retrait d'affectation",
    async () => {
      const now = new Date("2026-11-14T15:56:14.536Z");
      const present = fixture({now, assignedPeriodLists: [[], ["p1"]]});
      const first = await autoLowerClosedFlags(present.db, present.admin, now);
      assert.equal(first.lowered, 0);
      assert.equal(first.errors, 0);
      const removed = fixture({now, assignedPeriodLists: [[], []]});
      const second = await autoLowerClosedFlags(removed.db, removed.admin, now);
      assert.equal(second.lowered, 1);
      assert.equal(second.errors, 0);
    });

test("fermeture avec drapeau déjà affalé : seul le bandeau évolue",
    async () => {
      const ctx = fixture({
        now: new Date("2026-11-13T18:00:00Z"),
        rootPosition: "affale",
        status: "Baignade non surveillée temporairement",
      });
      const r = await autoLowerClosedFlags(ctx.db, ctx.admin, ctx.now);
      assert.equal(r.lowered, 0);
      assert.equal(r.statusUpdated, 1);
      assert.equal(ctx.writes.length, 1);
      assert.equal(ctx.writes[0].data.statutBaignade,
          "Baignade non surveillée");
    });

test("ouverture avec drapeau affalé : retour au bandeau temporaire",
    async () => {
      const ctx = fixture({
        now: new Date("2026-11-13T10:00:00Z"),
        rootPosition: "affale", status: "Baignade non surveillée",
      });
      const r = await autoLowerClosedFlags(ctx.db, ctx.admin, ctx.now);
      assert.equal(r.lowered, 0);
      assert.equal(r.statusUpdated, 1);
      assert.equal(ctx.writes.length, 1);
      assert.equal(ctx.writes[0].data.statutBaignade,
          "Baignade non surveillée temporairement");
    });
