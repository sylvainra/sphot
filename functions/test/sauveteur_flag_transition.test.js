"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {evaluateFlagTransition} = require("../sauveteur_flag_transition");

const oldFlag = {flagColor: "green", flagPosition: "hisse"};

test("interdit couleur verte hissée vers jaune même en affalant", () => {
  const transition = evaluateFlagTransition(oldFlag, {
    flagColor: "yellow", flagPosition: "affale",
  });
  assert.equal(transition.error, "flag_color_requires_lowered");
});

test("interdit modification de couleur avec le drapeau hissé", () => {
  const transition = evaluateFlagTransition(oldFlag, {
    flagColor: "red", flagPosition: "hisse",
  });
  assert.equal(transition.error, "flag_color_requires_lowered");
});

test("affalage seul autorisé et journalisé individuellement", () => {
  const transition = evaluateFlagTransition(oldFlag, {
    flagColor: "green", flagPosition: "affale",
  });
  assert.equal(transition.error, undefined);
  assert.equal(transition.flagWasLowered, true);
  assert.equal(transition.flagWasRaised, false);
  assert.deepEqual(transition.journalLines, [
    "Position du drapeau : Hissé → Affalé",
  ]);
});

test("couleur change uniquement affalé avant et après", () => {
  const transition = evaluateFlagTransition(
      {flagColor: "green", flagPosition: "affale"},
      {flagColor: "yellow", flagPosition: "affale"},
  );
  assert.equal(transition.error, undefined);
  assert.deepEqual(transition.journalLines, [
    "Couleur du drapeau : Vert → Jaune",
  ]);
});

test("impossible de changer couleur et hisser en une seule requête", () => {
  const transition = evaluateFlagTransition(
      {flagColor: "green", flagPosition: "affale"},
      {flagColor: "yellow", flagPosition: "hisse"},
  );
  assert.equal(transition.error, "flag_color_requires_lowered");
});

test("hissage sans changement de couleur autorisé et journalisé", () => {
  const transition = evaluateFlagTransition(
      {flagColor: "yellow", flagPosition: "affale"},
      {flagColor: "yellow", flagPosition: "hisse"},
  );
  assert.equal(transition.flagWasRaised, true);
  assert.deepEqual(transition.journalLines, [
    "Position du drapeau : Affalé → Hissé",
  ]);
});

test("signaux additionnels n'altèrent pas la couleur enregistrée", () => {
  const transition = evaluateFlagTransition(
      {flagColor: "red", flagPosition: "hisse"},
      {flagColor: "red", flagPosition: "hisse", purpleFlagActive: true},
  );
  assert.equal(transition.error, undefined);
  assert.deepEqual(transition.journalLines, [
    "Drapeau violet : Activé",
  ]);
  assert.equal(transition.requiresOpenSurveillance, true);
});

test("première initialisation exige le drapeau affalé", () => {
  assert.equal(
      evaluateFlagTransition({}, {
        flagColor: "green", flagPosition: "hisse",
      }).error,
      "flag_color_requires_lowered",
  );
  assert.equal(
      evaluateFlagTransition({}, {
        flagColor: "green", flagPosition: "affale",
      }).error,
      undefined,
  );
});

test("refuse des positions ou couleurs absentes et inconnues", () => {
  for (const invalid of [
    null,
    {},
    {flagColor: "purple", flagPosition: "affale"},
    {flagColor: "green", flagPosition: "levé"},
  ]) {
    assert.equal(
        evaluateFlagTransition(oldFlag, invalid).error,
        "invalid_flag_state",
    );
  }
});

test("transaction atomique, auteur et droits restent présents", () => {
  const source = fs.readFileSync(
      path.join(__dirname, "../index.js"), "utf8",
  );
  const handler = source.split("exports.updateSauveteurLiveState =")[1]
      .split("exports.")[0];
  assert.match(handler, /resolveSauveteurSession/);
  assert.match(handler, /context\.sphotMode !== "ON"/);
  assert.match(handler, /context\.realtimeSpotIds\.includes\(spotId\)/);
  assert.match(handler, /db\.runTransaction\(/);
  assert.match(handler, /evaluateFlagTransition\(previousLiveFlag/);
  assert.match(handler, /transaction\.set\(mainCouranteReference/);
  assert.match(handler, /transaction\.set\(auditReference/);
  assert.match(handler, /login: session\.login/);
  assert.match(handler, /flag_color_requires_lowered/);
});

test("toutes les manœuvres manuelles exigent des horaires ouverts", () => {
  const state = {
    flagColor: "green", flagPosition: "affale",
    purpleFlagActive: false, windsockActive: false,
  };
  const changes = [
    {...state, flagColor: "yellow"},
    {...state, flagPosition: "hisse"},
    {...state, purpleFlagActive: true},
    {...state, windsockActive: true},
  ];
  for (const next of changes) {
    assert.equal(
        evaluateFlagTransition(state, next).requiresOpenSurveillance, true,
    );
  }
  const hissed = {...state, flagPosition: "hisse"};
  assert.equal(evaluateFlagTransition(hissed, state)
      .requiresOpenSurveillance, true);
  assert.equal(evaluateFlagTransition(state, state)
      .requiresOpenSurveillance, false);
});

test("désactivation violette et manche à air autorisée hors horaires", () => {
  const prior = {
    flagColor: "yellow", flagPosition: "affale",
    purpleFlagActive: true, windsockActive: true,
  };
  const after = {
    ...prior, purpleFlagActive: false, windsockActive: false,
  };
  const transition = evaluateFlagTransition(prior, after);
  assert.equal(transition.requiresOpenSurveillance, false);
  assert.deepEqual(transition.journalLines, [
    "Drapeau violet : Désactivé",
    "Manche à air : Désactivée",
  ]);
});

test("le serveur vérifie les horaires pour toute manœuvre active", () => {
  const source = fs.readFileSync(
      path.join(__dirname, "../index.js"), "utf8",
  );
  const handler = source.split("exports.updateSauveteurLiveState =")[1]
      .split("exports.")[0];
  assert.match(handler, /flagTransition\.requiresOpenSurveillance/);
  assert.match(handler, /surveillanceWindow\(/);
});
