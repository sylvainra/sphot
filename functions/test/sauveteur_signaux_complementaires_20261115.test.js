"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const {evaluateFlagTransition} = require("../sauveteur_flag_transition");

const root = path.join(__dirname, "../..");
const read = (file) => fs.readFileSync(path.join(root, file), "utf8");

test("aucun retrait du violet ou de la manche avec le principal hissé", () => {
  const previous = {flagColor: "green", flagPosition: "hisse",
    purpleFlagActive: true, windsockActive: true};
  for (const field of ["purpleFlagActive", "windsockActive"]) {
    const result = evaluateFlagTransition(
        previous, {...previous, [field]: false},
    );
    assert.equal(result.error, "supplementary_requires_lowered");
  }
});

test("on peut sélectionner ou retirer les deux signaux affalés", () => {
  const before = {flagColor: "green", flagPosition: "affale",
    purpleFlagActive: true, windsockActive: true};
  const after = {...before, purpleFlagActive: false, windsockActive: false};
  assert.equal(evaluateFlagTransition(before, after).error, undefined);
  const restored = evaluateFlagTransition(after, before);
  assert.equal(restored.error, undefined);
  assert.equal(restored.requiresOpenSurveillance, true);
});

test("les signaux sélectionnés restent présents lors du hissage", () => {
  const before = {flagColor: "yellow", flagPosition: "affale",
    purpleFlagActive: true, windsockActive: true};
  const raised = {...before, flagPosition: "hisse"};
  const result = evaluateFlagTransition(before, raised);
  assert.equal(result.error, undefined);
  assert.equal(result.flagWasRaised, true);
  const lower = evaluateFlagTransition(raised, before);
  assert.equal(lower.error, undefined);
});

test("libellés fixes et blocage des deux boutons Android", () => {
  const source = read(
      "lib/pages/sauveteur/sauveteur_actions_rapides_page.dart",
  );
  assert.match(source, /label:\s*'Violet',/);
  assert.match(source, /label:\s*'Manche à air',/);
  assert.doesNotMatch(source, /'Affaler violet'|'Hisser violet'/);
  assert.doesNotMatch(source, /'Affaler manche à air'|'Hisser manche à air'/);
  const matches = source.match(
      /if \(_confirmedFlagPosition != 'Affalé'\) \{/g,
  ) || [];
  assert.equal(matches.length, 2);
});

test("calendrier centré et origine automatique dans écran et PDF", () => {
  const source = read("lib/pages/sauveteur/sauveteur_main_courante.dart");
  assert.match(source, /viewportDimension/);
  assert.match(source, /centerOfDay = \(_selectedDay\.day - 1\) \* 39\.0/);
  assert.match(source, /automatic_surveillance_closure/);
  assert.match(source, /Déclenchement automatique selon les jours et\/ou/);
  const matches = source.match(
      /_flagEventAttributionLabel\(entry, author, role\),/g,
  ) || [];
  assert.equal(matches.length, 2);
});
