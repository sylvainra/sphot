const admin = require("firebase-admin");

admin.initializeApp();

/**
 * Reconstruit les projections publiques de TOUS les territoires existants.
 *
 * Ce script ne change ni les droits Admin, ni les abonnements, ni les
 * informations sauveteur. Il écrit seulement une date technique dans chaque
 * territoire pour relancer syncPublicSpotsForTerritory sur le serveur.
 * La présence sur la carte est indépendante des droits temps réel.
 *
 * @return {Promise<void>}
 */
async function rebuildPublicSpots() {
  const db = admin.firestore();
  const territories = await db.collection("territoires").get();

  for (let index = 0; index < territories.docs.length; index += 450) {
    const batch = db.batch();
    territories.docs.slice(index, index + 450).forEach((document) => {
      batch.set(
          document.ref,
          {
            publicProjectionRefreshAt:
              admin.firestore.FieldValue.serverTimestamp(),
          },
          {merge: true},
      );
    });
    await batch.commit();
  }

  console.log(
      `${territories.docs.length} territoire(s) transmis à la projection ` +
      "publique. Les droits et l'état temps réel sont recalculés par SPHOT.",
  );
}

rebuildPublicSpots()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
