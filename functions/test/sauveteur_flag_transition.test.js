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
    "Drapeau VERT affalé.",
  ]);
});

test("couleur change uniquement affalé avant et après", () => {
  const transition = evaluateFlagTransition(
      {flagColor: "green", flagPosition: "affale"},
      {flagColor: "yellow", flagPosition: "affale"},
  );
  assert.equal(transition.error, undefined);
  assert.deepEqual(transition.journalLines, [
    "Drapeau affalé : VERT → JAUNE.",
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
    "Drapeau JAUNE hissé.",
  ]);
});

test("signaux complémentaires : hissage interdit si principal hissé", () => {
  for (const key of ["purpleFlagActive", "windsockActive"]) {
    const next = {flagColor: "green", flagPosition: "hisse", [key]: true};
    const result = evaluateFlagTransition(oldFlag, next);
    assert.equal(result.error, "supplementary_requires_lowered");
  }
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
  assert.match(handler, /evaluateFlagTransition\(/);
  assert.match(handler, /previousEffectiveFlag/);
  assert.match(handler, /transaction\.set\(mainCouranteReference/);
  assert.match(handler, /transaction\.set\(auditReference/);
  assert.match(handler, /login: session\.login/);
  assert.match(handler, /flag_color_requires_lowered/);
});

test("couleur modifiable drapeau affalé ; horaires au serveur", () => {
  const colors = ["green", "yellow", "red"];
  for (const from of colors) {
    for (const to of colors) {
      if (to === from) continue;
      const transition = evaluateFlagTransition(
          {flagColor: from, flagPosition: "affale"},
          {flagColor: to, flagPosition: "affale"},
      );
      assert.equal(transition.error, undefined);
      assert.equal(transition.requiresOpenSurveillance, false);
      assert.equal(transition.journalLines.length, 1);
      assert.match(transition.journalLines[0], /Drapeau affalé :/);
      assert.equal(transition.flagWasRaised, false);
    }
  }
});

test("hors horaires : affalage autorisé et écrit dans la main courante", () => {
  for (const color of ["green", "yellow", "red"]) {
    const transition = evaluateFlagTransition(
        {flagColor: color, flagPosition: "hisse"},
        {flagColor: color, flagPosition: "affale"},
    );
    assert.equal(transition.error, undefined);
    assert.equal(transition.requiresOpenSurveillance, false);
    assert.equal(transition.flagWasLowered, true);
    const names = {green: "VERT", yellow: "JAUNE", red: "ROUGE"};
    assert.deepEqual(transition.journalLines, [
      `Drapeau ${names[color]} affalé.`,
    ]);
  }
});

test("horaires ouverts requis : tous hissages et signaux activés", () => {
  for (const color of ["green", "yellow", "red"]) {
    const previous = {
      flagColor: color, flagPosition: "affale",
      purpleFlagActive: false, windsockActive: false,
    };
    const transitions = [
      {...previous, flagPosition: "hisse"},
      {...previous, purpleFlagActive: true},
      {...previous, windsockActive: true},
    ];
    for (const next of transitions) {
      const result = evaluateFlagTransition(previous, next);
      assert.equal(result.error, undefined);
      assert.equal(result.requiresOpenSurveillance, true);
      assert.ok(result.journalLines.length > 0);
    }
  }
});

test("hors horaires : désactivations et initialisation", () => {
  const previous = {
    flagColor: "red", flagPosition: "affale",
    purpleFlagActive: true, windsockActive: true,
  };
  const disabled = evaluateFlagTransition(previous, {
    ...previous, purpleFlagActive: false, windsockActive: false,
  });
  assert.equal(disabled.requiresOpenSurveillance, false);
  assert.deepEqual(disabled.journalLines, [
    "Drapeau VIOLET affalé.",
    "Manche à air affalée.",
  ]);
  const initialized = evaluateFlagTransition({}, {
    flagColor: "yellow", flagPosition: "affale",
  });
  assert.equal(initialized.requiresOpenSurveillance, false);
  const same = evaluateFlagTransition(previous, previous);
  assert.equal(same.requiresOpenSurveillance, false);
  assert.deepEqual(same.journalLines, []);
});

test("activation et changement de couleur combinés exigent horaires ouverts",
    () => {
      const previous = {
        flagColor: "green", flagPosition: "affale",
        purpleFlagActive: false, windsockActive: false,
      };
      const result = evaluateFlagTransition(previous, {
        ...previous, flagColor: "yellow", purpleFlagActive: true,
      });
      assert.equal(result.error, undefined);
      assert.equal(result.requiresOpenSurveillance, true);
      assert.deepEqual(result.journalLines, [
        "Drapeau affalé : VERT → JAUNE.",
        "Drapeau VIOLET hissé.",
      ]);
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
    "Drapeau VIOLET affalé.",
    "Manche à air affalée.",
  ]);
});

test("journalisation serveur : changements atomiques", () => {
  const source = fs.readFileSync(
      path.join(__dirname, "../index.js"), "utf8",
  );
  const handler = source.split("exports.updateSauveteurLiveState =")[1]
      .split("exports.")[0];
  assert.match(handler, /flagTransition\.journalLines/);
  assert.match(handler, /if \(flagJournalLines\.length > 0\)/);
  assert.match(handler, /type: "Drapeau"/);
  assert.match(handler, /source: "automatic_flag_event"/);
  assert.match(handler, /transaction\.set\(mainCouranteReference/);
  assert.match(handler, /createdBy: \{/);
  assert.match(handler, /login: session\.login/);
});

test("le serveur vérifie les horaires pour toute manœuvre active", () => {
  const source = fs.readFileSync(
      path.join(__dirname, "../index.js"), "utf8",
  );
  const handler = source.split("exports.updateSauveteurLiveState =")[1]
      .split("exports.")[0];
  assert.match(handler, /if \(flagTransition\)/);
  assert.match(handler, /surveillanceWindowForSauveteurs\(/);
  assert.match(handler, /if \(!schedule\.open/);
  assert.doesNotMatch(handler, /source: "flag_preparation"/);
  assert.match(handler, /flagTransition\.colorChanged/);
});

test("preparation consommee : audit sans sentinelle Firestore", () => {
  const source = fs.readFileSync(
      path.join(__dirname, "../index.js"), "utf8");
  const handler = source.split("exports.updateSauveteurLiveState =")[1]
      .split("exports.")[0];
  const start = handler.indexOf(
      "const auditChanges = {...sanitizedChanges};");
  const end = handler.indexOf("transaction.set(auditReference, {", start);
  assert.ok(start >= 0 && end > start);
  const snippet = handler.slice(start, end);
  const vm = require("node:vm");
  const sentinel = {firestoreOperation: "DELETE"};
  const original = {liveFlag: {flagPosition: "hisse"},
    preparedFlag: sentinel};
  const context = {sanitizedChanges: original,
    previousPreparedFlag: {pending: true}, flagTransition: {}};
  const audit = vm.runInNewContext(snippet + "\nauditChanges", context);
  assert.equal(audit.preparedFlag, undefined);
  assert.equal(audit.preparedFlagConsumed, true);
  assert.equal(audit.liveFlag.flagPosition, "hisse");
  assert.equal(original.preparedFlag, sentinel);
  const withoutPrep = vm.runInNewContext(snippet + "\nauditChanges", {
    sanitizedChanges: {liveFlag: {flagPosition: "hisse"}},
    previousPreparedFlag: null, flagTransition: {},
  });
  assert.equal(withoutPrep.preparedFlagConsumed, undefined);
  assert.match(handler, /changes: auditChanges,/);
  assert.doesNotMatch(handler, /changes: sanitizedChanges,/);
});

test("les signaux complémentaires peuvent être hissés principal affalé", () => {
  const previous = {flagColor: "green", flagPosition: "affale",
    purpleFlagActive: false, windsockActive: false};
  for (const key of ["purpleFlagActive", "windsockActive"]) {
    const result = evaluateFlagTransition(previous, {...previous, [key]: true});
    assert.equal(result.error, undefined);
    assert.equal(result.requiresOpenSurveillance, true);
  }
});

test("aucun événement si le drapeau est déjà affalé", () => {
  const flag = {flagColor: "green", flagPosition: "affale",
    purpleFlagActive: false, windsockActive: false};
  const result = evaluateFlagTransition(flag, {...flag});
  assert.deepEqual(result.journalLines, []);
});
