// Prueba del contrato de creación de capas. No sustituye ejecutar el plugin en Figma.
const fs=require('node:fs');
const vm=require('node:vm');
const assert=require('node:assert/strict');
const path=require('node:path');
const root=__dirname;
const spec=JSON.parse(fs.readFileSync(path.join(root,'dashboard-editable.json'),'utf8'));
const code=fs.readFileSync(path.join(root,'Figma/code.js'),'utf8');
const manifest=JSON.parse(fs.readFileSync(path.join(root,'Figma/manifest.json'),'utf8'));
assert.deepEqual(manifest.networkAccess.allowedDomains,['none']);
assert.deepEqual(manifest.editorType,['figma']);
let expectedText=0;
function validate(def,parent){
 assert(def.width>0&&def.height>0);
 if(parent){assert(def.x>=0&&def.y>=0,def.name);assert(def.x+def.width<=parent.width+.1,def.name);assert(def.y+def.height<=parent.height+.1,def.name);}
 if(def.type==='text') expectedText++;
 for(const child of def.children||[])validate(child,def);
}
spec.frames.forEach(def=>validate(def));
async function run(failAtIcon=0,font='Inter'){
 let iconCount=0;
 const all=[];
 function node(type){return {type,children:[],x:0,y:0,appendChild(child){if(child.parent){const a=child.parent.children;a.splice(a.indexOf(child),1);}child.parent=this;this.children.push(child);},resize(w,h){this.width=w;this.height=h;},remove(){if(this.parent){const a=this.parent.children;a.splice(a.indexOf(this),1);this.parent=null;}this.removed=true;}};}
 const page=node('PAGE');
 return new Promise((resolve,reject)=>{
  const timeout=setTimeout(()=>reject(new Error('Importador no terminó')),2000);
  const figma={currentPage:page,viewport:{scrollAndZoomIntoView(nodes){assert.equal(nodes.length,4);}},
   async listAvailableFontsAsync(){return ['Regular','Medium','Semi Bold','Bold'].map(style=>({fontName:{family:font,style}}));},async loadFontAsync(){},
   createFrame(){const n=node('FRAME');all.push(n);page.appendChild(n);return n;},
   createText(){const n=node('TEXT');all.push(n);page.appendChild(n);return n;},
   createNodeFromSvg(svg){iconCount++;if(iconCount===failAtIcon)throw new Error('fallo controlado');assert(svg.startsWith('<svg'));const n=node('SVG');all.push(n);page.appendChild(n);return n;},
   closePlugin(message){clearTimeout(timeout);resolve({page,all,message});}};
  try{vm.runInNewContext(code,{figma,Map},{timeout:1500});}catch(error){clearTimeout(timeout);reject(error);}
 });
}
(async()=>{
 for(const font of ['Inter','Roboto']){
  const result=await run(0,font);
  assert.equal(result.page.children.length,4);
  assert.equal(result.page.selection.length,4);
  const texts=result.all.filter(n=>n.type==='TEXT');assert.equal(texts.length,expectedText);
  assert(texts.every(n=>n.fontName.family===font&&n.characters.length>0));
 }
 const failed=await run(3);assert.equal(failed.page.children.length,0,'Debe limpiar la importación parcial');
 console.log(`Contrato del importador: 4 frames, ${expectedText} textos nativos, fuentes Inter/Roboto y limpieza ante fallo verificados.`);
})().catch(error=>{console.error(error);process.exitCode=1;});
