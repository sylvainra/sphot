"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const read = (file) => fs.readFileSync(path.join(__dirname, file), "utf8");

test("pas de nouvelle préparation hors horaires", () => {
  const server = read("../index.js");
  const handler = server.split("exports.updateSauveteurLiveState =")[1]
      .split("exports.")[0];
  assert.doesNotMatch(handler, /source: "flag_preparation"/);
  assert.match(handler, /flagTransition\.colorChanged/);
  assert.match(handler, /statutBaignade = !schedule\.open/);
  assert.match(handler, /journalLines\.length === 0/);
});

test("fermeture automatique sans préparation ou doublon", () => {
  const server = read("../sauveteur_flag_auto_lower.js");
  assert.doesNotMatch(server, /scheduled_preparation_publication/);
  assert.match(server, /statutBaignade: "Baignade non surveillée"/);
  assert.match(server, /Drapeau VIOLET affalé automatiquement/);
  assert.match(server, /actionTaken: ""/);
  for (const signal of ["flagPosition", "purpleFlagActive",
    "windsockActive"]) {
    assert.ok(server.includes(JSON.stringify("liveFlag." + signal)));
  }
});

test("message Admin et bandeaux distincts sur Android", () => {
  const app = fs.readFileSync(path.resolve(__dirname,
      "../../lib/pages/sauveteur/sauveteur_actions_rapides_page.dart"),
  "utf8");
  assert.match(app, /en dehors des jours et\/ou/);
  assert.match(app, /attribuée à ce poste par SPHOT ADMIN/);
  assert.match(app, /_confirmedStatutBaignade/);
  assert.match(app, /'BAIGNADE NON SURVEILLÉE'/);
  assert.doesNotMatch(app, /Heure serveur UTC/);
});
