"use strict";

// Difference juridique fiable entre deux versions ARCHIVEES/PUBLIEES.
// Seuls les paragraphes modifies sont retournes, sans resumer leur sens.
// Aucune interpretation automatique des obligations juridiques.
function paragraphs(value) {
  if (typeof value !== "string") return [];
  return value.replace(/\r\n?/g, "\n").trim()
      .split(/\n\s*\n/g).map((v) => v.trim()).filter(Boolean);
}

// Plus longue sous-sequence commune : les passages inchanges restent caches.
// Limite defensive : un article trop volumineux affiche un bloc complet.
function changedBlocks(before, after) {
  const previous = paragraphs(before);
  const current = paragraphs(after);
  if (previous.length > 150 || current.length > 150) {
    return [{before: previous.join("\n\n"), after: current.join("\n\n")}];
  }
  const m = previous.length;
  const n = current.length;
  const matrix = Array.from({length: m + 1}, () => Array(n + 1).fill(0));
  for (let i = m - 1; i >= 0; i--) {
    for (let j = n - 1; j >= 0; j--) {
      matrix[i][j] = previous[i] === current[j] ?
        matrix[i + 1][j + 1] + 1 :
        Math.max(matrix[i + 1][j], matrix[i][j + 1]);
    }
  }
  let i = 0; let j = 0;
  const blocks = [];
  let old = []; let now = [];
  const flush = () => {
    if (old.length || now.length) {
      blocks.push({before: old.join("\n\n"), after: now.join("\n\n")});
    }
    old = []; now = [];
  };
  while (i < m || j < n) {
    if (i < m && j < n && previous[i] === current[j]) {
      flush();
      i++; j++;
    } else if (j < n && (i === m ||
        matrix[i][j + 1] >= matrix[i + 1][j])) {
      now.push(current[j++]);
    } else {
      old.push(previous[i++]);
    }
  }
  flush();
  return blocks;
}

function validChapters(value) {
  if (!Array.isArray(value) || !value.length || value.length > 60) {
    return false;
  }
  const ids = new Set();
  for (const item of value) {
    if (!item || typeof item !== "object" ||
        typeof item.id !== "string" || !item.id.trim() ||
        typeof item.title !== "string" ||
        typeof item.content !== "string" || ids.has(item.id)) return false;
    ids.add(item.id);
  }
  return true;
}

// Compare par identifiant d'article : ajouts, retraits, titres, ordre,
// et plusieurs passages ou articles modifies dans la meme publication.
function buildAdminChanges(previous, current, {baselineVersionId,
  baselineKind, versionId}) {
  if (!validChapters(previous) || !validChapters(current)) return null;
  const priorById = new Map(previous.map((x, index) =>
    [x.id, {...x, index}]));
  const currentById = new Map(current.map((x, index) =>
    [x.id, {...x, index}]));
  const ids = [...new Set([...previous.map((x) => x.id),
    ...current.map((x) => x.id)])];
  const articles = [];
  for (const id of ids) {
    const prior = priorById.get(id);
    const next = currentById.get(id);
    const title = next?.title || prior?.title || "";
    const titleChanged = prior && next && prior.title !== next.title;
    const orderChanged = prior && next && prior.index !== next.index;
    const blocks = changedBlocks(prior?.content || "", next?.content || "");
    if (!titleChanged && !orderChanged && !blocks.length) continue;
    articles.push({id, title, beforeTitle: prior?.title || "",
      titleChanged: Boolean(titleChanged), orderChanged: Boolean(orderChanged),
      removed: !next, added: !prior, blocks});
  }
  return {baselineVersionId, baselineKind, versionId,
    articles, articleCount: articles.length};
}

module.exports = {paragraphs, changedBlocks, buildAdminChanges};
