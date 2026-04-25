const admin = require("firebase-admin");
const fs = require("fs");
const csv = require("csv-parser");

const serviceAccount = require("./serviceAccountKey.json");

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();
const results = [];

fs.createReadStream("spots.csv")
  .pipe(csv())
  .on("data", (data) => results.push(data))
  .on("end", async () => {
    console.log(`📊 ${results.length} lignes trouvées`);

    for (const row of results) {
      try {
        const id = `SPHOT_${row.id_sphot}`;
        const lat = parseFloat(row.latitude);
        const lng = parseFloat(row.longitude);

        if (Number.isNaN(lat) || Number.isNaN(lng)) {
          console.log(`❌ Coordonnées invalides pour ${id}`);
          continue;
        }

        const data = {
          id_sphot: row.id_sphot || "",
          name: row.nom_secours || "",
          nom_sphot: row.nom_sphot || "",
          lat,
          lng,
          type_sphot: row.type_sphot || "",
          statut_baignade: row.statut_baignade || "",
          periode: row.periode || "",
          heure_debut: row.heure_debut || "",
          heure_fin: row.heure_fin || "",
          activite: row.activite || "",
        };

        await db.collection("spots").doc(id).set(data, { merge: true });
        console.log(`✅ ${id} importé`);
      } catch (err) {
        console.error("❌ Erreur sur ligne :", row, err);
      }
    }

    console.log("🎉 Import terminé !");
    process.exit();
  });