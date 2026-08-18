const admin = require("firebase-admin");

admin.initializeApp();

/**
 * Relance la projection publique pour les administrateurs approuvés.
 *
 * @return {Promise<void>}
 */
async function rebuildPublicSpots() {
  const db = admin.firestore();
  const admins = await db.collection("admins")
      .where("accessStatus", "==", "approved")
      .get();

  for (let index = 0; index < admins.docs.length; index += 450) {
    const batch = db.batch();
    admins.docs.slice(index, index + 450).forEach((document) => {
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
      `${admins.size} administrateur(s) approuvé(s) transmis ` +
      "à la projection publique.",
  );
}

rebuildPublicSpots()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
