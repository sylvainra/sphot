"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const pub = require("../legal_pack_publication");

// Source folder path is passed by the optional environment variable in
// cross-repo tests, or as assets/legal/test_corpus in the actual project.
function sourcePath(spec) {
  const root = process.env.SPHOT_LEGAL_CORPUS_TEST_ROOT || path.resolve(__dirname, "../..");
  return path.join(root, "assets/legal/test_corpus", {
    adminCgv: "cgv_admin.md", advertiserCgv: "cgv_publicitaire.md",
    cgu: "cgu_grand_public.md", sauveteurCgu: "cgu_sauveteur.md",
    sauveteurCharter: "charte_sauveteur.md",
  }[spec.id]);
}
function parse(source) {
  const rows=[];let title=null,lines=[];
  function flush(){if(title!==null)rows.push({title,content:lines.join("\n").trim()});lines=[];}
  for(const line of String(source).replace(/\r\n/g,"\n").split("\n")) {
    if(line.startsWith("## ")){flush();title=line.slice(3).trim();}
    else if(title!==null)lines.push(line);
  }flush();return rows;
}
const sha = (value) => require("node:crypto").createHash("sha256")
  .update(JSON.stringify(value)).digest("hex");
class Ref {
  constructor(db,p) {this.db=db;this.path=p;this.id=p.split("/").at(-1);}
  collection(n) {return new Col(this.db,this.path+"/"+n);}
  async get(){return this.db.snapshot(this.path);}
}
class Col {
  constructor(db,p){this.db=db;this.path=p;}
  doc(id){return new Ref(this.db,this.path+"/"+id);}
  async get(){return this.db.query(this.path);}
}
class FakeDb {
  constructor(){this.docs=new Map();}
  collection(n){return new Col(this,n);}
  snapshot(key){const data=this.docs.get(key);return {exists:data!==undefined,
    id:key.split("/").at(-1), ref:new Ref(this,key),
    data:()=>data===undefined?undefined:structuredClone(data)};}
  query(p){const docs=[];for(const key of this.docs.keys()){
    if(key.startsWith(p+"/") && key.slice(p.length+1).split("/").length===1)
      docs.push(this.snapshot(key));
  }docs.sort((a,b)=>a.id.localeCompare(b.id));return {docs,empty:docs.length===0};}
  async runTransaction(fn){const actions=[];
    const tx={get:(q)=>q.get(),set:(ref,data,opts)=>actions.push({op:"set",ref,data,opts}),
      update:(ref,data)=>actions.push({op:"update",ref,data}),
      create:(ref,data)=>actions.push({op:"create",ref,data}),
      delete:(ref)=>actions.push({op:"delete",ref})};
    const result=await fn(tx);
    // No mutation before the transaction completes successfully.
    const updated=new Map(this.docs);
    for(const {op,ref,data,opts} of actions){
      if(op==="delete")updated.delete(ref.path);
      else if(op==="create" && updated.has(ref.path))throw Error("ALREADY_EXISTS");
      else if(op==="update" && !updated.has(ref.path))throw Error("NOT_FOUND");
      else if(op==="set" && opts?.merge)updated.set(ref.path,{...updated.get(ref.path),...data});
      else if(op==="update")updated.set(ref.path,{...updated.get(ref.path),...data});
      else updated.set(ref.path,data);
    }
    this.docs=updated;return result;
  }
}
function fixture() {
  const db=new FakeDb();
  const firestore=()=>db;
  firestore.FieldValue={serverTimestamp:()=>({__serverTimestamp:true})};
  const admin={firestore};
  const token={role:"SPHOT_SUPER_ADMIN",sphotSuperAdmin:true,
    uid:"sphot-super-admin-"+"a".repeat(32),
    sphotSaSessionExpiresAt:Date.now()+100000};
  db.docs.set("legalDocuments/metadata",{version:"1.0",publishedAt:"previous"});
  for(const common of ["privacyPolicy","rgpdNotice"]){
    db.docs.set("legalDocuments/"+common,{version:"1.0",revision:1});
    db.docs.set("legalDocuments/"+common+"/chapters/01",{title:common,content:"Existing required text"});
  }
  const legacy=[];
  for(let i=0;i<12;i++){
    const id=String(i+1).padStart(2,"0");
    db.docs.set("legalDocuments/cgu/chapters/"+id,{title:"Legacy "+id,content:"Previous text"});
    legacy.push({id,title:"Legacy "+id,content:"Previous text",order:i+1,isActive:true});
  }
  db.docs.set("legalDocuments/cgu",{version:"1.0"});
  const rows=[];
  for (const s of pub.DOCUMENTS) {
    const input=parse(fs.readFileSync(sourcePath(s),"utf8"));
    assert.equal(input.length,s.count);
    const chapters=input.map((r,i)=>({id:String(i+1).padStart(2,"0"),...r,
      order:i+1,isActive:true}));
    const active=s.id==="cgu"?{version:"1.0",revision:-1,published:false,chapters:legacy}:
      {version:"1.0",revision:-1,published:false,chapters:[]};
    const draft={documentId:s.id,status:"draft",draftRevision:0,
      chapters,baseHash:sha(active),baseRevision:-1,
      importSource:"sphot_c4_validated_legal_import_20261106_v1",
      sourceProject:"sphot-c4-test-20261029",sourceDocumentId:s.source,
      sourceVersion:"1.0",sourceRevision:1,importedC4Hash:s.sha};
    db.docs.set("legalDocumentDrafts/"+s.id,draft);
    rows.push(draft);
  }
  return {db,admin,token,rows};
}

test("cinq textes intégraux, 54 articles et empreintes exactes",()=>{
  assert.equal(pub.DOCUMENTS.reduce((n,s)=>n+s.count,0),54);
  for(const s of pub.DOCUMENTS){
    const rows=parse(fs.readFileSync(sourcePath(s),"utf8"))
      .map((r,i)=>({id:String(i+1).padStart(2,"0"),...r,order:i+1,isActive:true}));
    assert.equal(pub.sourceDigest(rows),s.sha);
  }
});
test("interdit articles modifiés, vides et IDs ambigus",()=>{
  const {rows}=fixture();
  const s=pub.DOCUMENTS[0];
  assert.throws(()=>pub.canonical([{id:"01",title:"X",content:"",order:1,isActive:true}]));
  assert.throws(()=>pub.canonical([{id:"02",title:"X",content:"Y",order:1,isActive:true}]));
  assert.throws(()=>pub.checkDraft({exists:true,data:()=>({...rows[0],chapters:[
    {...rows[0].chapters[0],content:"MODIFIÉ"},...rows[0].chapters.slice(1)]})},s));
});
test("version juridique globale strictement incrémentée",()=>{
  assert.equal(pub.nextVersion("1.0"),"1.1");
  assert.equal(pub.nextVersion("2.9"),"2.10");
  assert.throws(()=>pub.nextVersion("test"));
});
test("confirmation explicite et champs HTTP stricts",()=>{
  assert.throws(()=>pub.validateInput({action:"publish",confirm:false,expectedVersion:"1.0",expectedPackHash:"a".repeat(64)}));
  assert.throws(()=>pub.validateInput({action:"status",debug:true}));
  assert.equal(pub.validateInput({action:"publish",confirm:true,expectedVersion:"1.0",
    expectedPackHash:"a".repeat(64)}).action,"publish");
});
test("validation atomique puis publication de cinq documents, sans toucher RGPD/confidentialité",async()=>{
  const {db,admin,token}=fixture();
  const now=Date.now();
  const beforePrivacy=JSON.stringify(db.docs.get("legalDocuments/privacyPolicy"));
  const beforeRgpd=JSON.stringify(db.docs.get("legalDocuments/rgpdNotice"));
  const state=await pub.action({admin,token,input:{action:"status"},now});
  assert.equal(state.currentVersion,"1.0");
  assert.equal(state.ready,false);
  const validated=await pub.action({admin,token,input:{action:"validate"},now});
  assert.equal(validated.validated,true);
  assert.equal(validated.documentCount,5);
  const state2=await pub.action({admin,token,input:{action:"status"},now});
  assert.equal(state2.ready,true);
  assert.equal(state2.packHash,validated.packHash);
  const published=await pub.action({admin,token,input:{action:"publish",confirm:true,
    expectedVersion:"1.0",expectedPackHash:state2.packHash},now});
  assert.equal(published.version,"1.1");
  assert.equal(published.documentsPublished,5);
  assert.equal(db.docs.get("legalDocuments/metadata").legalVersion,"1.1");
  assert.equal(db.docs.get("legalDocuments/metadata").packPath,"legalPacks/versions/items/1_1");
  assert.equal(db.query("legalDocuments/cgu/chapters").docs.length,13);
  assert.ok(db.docs.has("legalVersions/cgu_legacy_unversioned"));
  assert.ok(db.docs.has("legalVersions/1_1"));
  assert.ok(db.docs.has("legalPacks/versions/items/1_1"));
  for(const s of pub.DOCUMENTS){
    assert.equal(db.docs.get("legalDocuments/"+s.id).revision,0);
    assert.equal(db.docs.get("legalDocuments/"+s.id).version,"1.1");
    assert.equal(db.docs.get("legalDocuments/"+s.id).published,true);
    assert.equal(db.query("legalDocuments/"+s.id+"/chapters").docs.length,s.count);
    assert.equal(db.docs.get("legalDocumentDrafts/"+s.id).status,"published");
  }
  assert.equal(JSON.stringify(db.docs.get("legalDocuments/privacyPolicy")),beforePrivacy);
  assert.equal(JSON.stringify(db.docs.get("legalDocuments/rgpdNotice")),beforeRgpd);
  await assert.rejects(pub.action({admin,token,input:{action:"publish",confirm:true,
    expectedVersion:"1.0",expectedPackHash:state2.packHash},now}));
});
test("un seul texte changé avant la validation bloque tout le pack",async()=>{
  const {db,admin,token}=fixture();
  db.docs.get("legalDocumentDrafts/advertiserCgv").chapters[0].content="PIRATE";
  const state=JSON.stringify([...db.docs]);
  await assert.rejects(pub.action({admin,token,input:{action:"validate"}}));
  assert.equal(JSON.stringify([...db.docs]),state);
});
test("un document actif modifié rend la publication impossible",async()=>{
  const {db,admin,token}=fixture();
  await pub.action({admin,token,input:{action:"validate"}});
  const reference="legalDocuments/cgu/chapters/01";
  db.docs.get(reference).content="Écrit directement par client";
  const state=JSON.stringify([...db.docs]);
  const valid=await pub.action({admin,token,input:{action:"status"}});
  await assert.rejects(pub.action({admin,token,input:{action:"publish",confirm:true,
    expectedVersion:"1.0",expectedPackHash:valid.packHash}}));
  assert.equal(JSON.stringify([...db.docs]),state);
});
test("droits Super Admin obligatoires pour toutes les opérations",async()=>{
  const {admin}=fixture();
  await assert.rejects(pub.action({admin,token:{uid:"other",role:"admin"},
    input:{action:"status"}}));
});
