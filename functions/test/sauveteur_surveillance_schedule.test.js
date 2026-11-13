"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {surveillanceWindow, localClock} =
  require("../sauveteur_surveillance_schedule");

const period = {
  id: "été-2026",
  label: "ÉTÉ 2026 — DU 12/06/2026 AU 30/11/2026 — DE 11h00 À 19h00",
  startDate: new Date("2026-06-11T22:00:00.000Z"),
  endDate: new Date("2026-11-29T23:00:00.000Z"),
  startHour: "11:00",
  endHour: "19:00",
  timeZone: "Europe/Paris",
};
const spot = {periodesSurveillance: [period.label]};

test("heure de surveillance Admin: ouverture à 11h, fermeture à 19h", () => {
  const before = surveillanceWindow(
      spot, [period], new Date("2026-11-13T09:59:00Z"));
  const opened = surveillanceWindow(
      spot, [period], new Date("2026-11-13T10:00:00Z"));
  const lastMinute = surveillanceWindow(
      spot, [period], new Date("2026-11-13T17:59:00Z"));
  const closed = surveillanceWindow(
      spot, [period], new Date("2026-11-13T18:00:00Z"));

  assert.equal(before.open, false);
  assert.equal(opened.open, true);
  assert.equal(opened.closesAt.toISOString(), "2026-11-13T18:00:00.000Z");
  assert.equal(lastMinute.open, true);
  assert.equal(closed.open, false);
});

test("ne prend pas les périodes non attribuées au poste", () => {
  const selection = surveillanceWindow(
      {periodesSurveillance: ["AUTRE PÉRIODE"]},
      [period],
      new Date("2026-11-13T12:00:00Z"),
  );
  assert.equal(selection.configured, false);
  assert.equal(selection.open, false);
});

test("prend en charge les identifiants stables de période", () => {
  const selection = surveillanceWindow(
      {periodesSurveillanceIds: ["été-2026"]},
      [period],
      new Date("2026-11-13T12:00:00Z"),
  );
  assert.equal(selection.open, true);
});

test("n'ouvre pas un poste hors saison", () => {
  const evaluation = surveillanceWindow(
      spot, [period], new Date("2026-12-03T12:00:00Z"),
  );
  assert.equal(evaluation.open, false);
});

test("prend en compte le changement d'heure français", () => {
  const summerPeriod = {
    ...period,
    startDate: new Date("2026-03-28T23:00:00Z"),
    endDate: new Date("2026-04-01T22:00:00Z"),
  };
  const window = surveillanceWindow(
      spot, [summerPeriod], new Date("2026-03-29T09:00:00Z"),
  );
  assert.equal(window.open, true);
  assert.equal(window.closesAt.toISOString(), "2026-03-29T17:00:00.000Z");
  const clock = localClock(new Date("2026-03-29T09:00:00Z"),
      "Europe/Paris");
  assert.equal(clock.hour, 11);
});

test("ne traite pas un horaire absent comme une autorisation", () => {
  const broken = {
    ...period,
    endHour: "",
  };
  const window = surveillanceWindow(
      spot, [broken], new Date("2026-11-13T12:00:00Z"),
  );
  assert.equal(window.configured, true);
  assert.equal(window.open, false);
});

test("les plages qui se chevauchent ferment à la dernière échéance", () => {
  const morning = {...period, endHour: "18:00"};
  const evening = {...period, startHour: "17:30", endHour: "20:00"};
  const window = surveillanceWindow(
      spot, [morning, evening], new Date("2026-11-13T17:00:00Z"));
  assert.equal(window.open, true);
  assert.equal(window.closesAt.toISOString(), "2026-11-13T19:00:00.000Z");
});

test("aucune période = aucune ouverture présumée", () => {
  const window = surveillanceWindow(
      {periodesSurveillance: []}, [],
      new Date("2026-11-13T12:00:00Z"));
  assert.equal(window.open, false);
  assert.equal(window.configured, false);
});
