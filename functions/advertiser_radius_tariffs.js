"use strict";

// Grille de reference VALIDEE le 18/10/2026 :
// 5 km, 15 km, 50 km, 150 km, 300 km et PAYS ENTIER
// x CARTE SPHOT, FICHES SPHOT, PACK TOTAL
// x 1 semaine, 2 semaines, 1 mois, 2 mois, 6 mois, 1 an.
// Tous les prix sont des montants en euros HT, fixes, et versionnables.
// Aucune ancienne grille de 90 prix n'est utilisee.
const LEVELS = [
  "radius_5km", "radius_15km", "radius_50km",
  "radius_150km", "radius_300km", "country",
];
const OFFERS = ["map", "premium", "pack"];
const DURATIONS = [
  "1 semaine", "2 semaines", "1 mois",
  "2 mois", "6 mois", "1 an",
];
const MATRIX = [
  [
    [
      49,
      95,
      149,
      249,
      599,
      999
    ],
    [
      99,
      189,
      299,
      499,
      1199,
      1999
    ],
    [
      129,
      239,
      379,
      629,
      1519,
      2539
    ]
  ],
  [
    [
      89,
      159,
      249,
      419,
      999,
      1669
    ],
    [
      159,
      289,
      449,
      759,
      1799,
      3009
    ],
    [
      199,
      369,
      569,
      969,
      2279,
      3809
    ]
  ],
  [
    [
      139,
      259,
      399,
      679,
      1599,
      2669
    ],
    [
      259,
      489,
      749,
      1269,
      2999,
      5019
    ],
    [
      329,
      619,
      949,
      1609,
      3799,
      6359
    ]
  ],
  [
    [
      209,
      379,
      590,
      999,
      2359,
      3949
    ],
    [
      379,
      709,
      1090,
      1859,
      4359,
      7299
    ],
    [
      489,
      899,
      1390,
      2369,
      5559,
      9309
    ]
  ],
  [
    [
      229,
      439,
      690,
      1190,
      2650,
      4450
    ],
    [
      419,
      799,
      1290,
      2230,
      4890,
      8090
    ],
    [
      539,
      1029,
      1690,
      2940,
      6490,
      10600
    ]
  ],
  [
    [
      250,
      490,
      790,
      1390,
      2900,
      4900
    ],
    [
      450,
      890,
      1490,
      2600,
      5400,
      8900
    ],
    [
      590,
      1150,
      1990,
      3500,
      7400,
      11900
    ]
  ]
];

function initialPrices() {
  const prices = {};
  for (let level = 0; level < LEVELS.length; level++) {
    for (let offer = 0; offer < OFFERS.length; offer++) {
      for (let duration = 0; duration < DURATIONS.length; duration++) {
        prices[level + ":" + offer + ":" + duration] =
          MATRIX[level][offer][duration];
      }
    }
  }
  return prices;
}

const PRICE_KEYS = Object.keys(initialPrices()).sort();

module.exports = {LEVELS, OFFERS, DURATIONS, PRICE_KEYS, initialPrices};
