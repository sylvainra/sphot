const admin = require("firebase-admin");

admin.initializeApp();

/**
 * Relance la projection publique pour les administrateurs approuvés.
 *
 * @return {Promise<void>}
 */
async function rebuildPublicSpots() {
  const db = admin.firestore();
  const [admins, requests] = await Promise.all([
    db.collection("admins")
        .where("accessStatus", "==", "approved")
        .get(),
    db.collection("adminRequests").get(),
  ]);
  const approvedRequests = requests.docs.filter((document) => {
    const data = document.data();
    const tracking = data.administrativeTracking || {};
    return data.status === "approved" ||
      tracking.status === "approved" ||
      data.accessPhase === "configuration_access";
  });
  const documents = [...admins.docs, ...approvedRequests];

  for (let index = 0; index < documents.length; index += 450) {
    const batch = db.batch();
    documents.slice(index, index + 450).forEach((document) => {
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
      `${documents.length} validation(s) administrative(s) transmise(s) ` +
      "à la projection publique.",
  );
}

rebuildPublicSpots()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });
