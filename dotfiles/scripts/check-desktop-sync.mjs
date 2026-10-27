// Isolated production-function checks; no desktop, account or profile access.
import assert from 'node:assert/strict';
import {readFileSync, mkdtempSync, existsSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {spawnSync} from 'node:child_process';
import vm from 'node:vm';
import {stripTypeScriptTypes} from 'node:module';
import test from 'node:test';
const shell=new URL('../config/shoji-shell/',import.meta.url);
const qml=name=>readFileSync(new URL(name,shell),'utf8');
function extract(source,name,prefix='    function '){
 const start=source.indexOf(prefix+name+'(');assert.ok(start>=0,`Missing production function: ${name}`);
 const body=source.indexOf('{',start);let depth=1,end=body+1;
 while(depth&&end<source.length){if(source[end]==='{')depth++;if(source[end]==='}')depth--;end++;}
 return source.slice(start,end);
}
test('stopped live renderer restarts with the same selection',()=>{
 const selection={layers:[{outputs:['A'],visibleOutputs:['A']}]},sent=[];
 const state=vm.createContext({restoring:false,busy:false,backend:{running:true},catalogReady:true,nativeWave:true,active:false,appliedSignature:JSON.stringify(selection),Wallpapers:{ready:true,saving:false,targetOutput:'',document:{live:selection},renderableLive:()=>selection},send:(action,data)=>sent.push({action,data})});
 vm.runInContext(extract(qml('LiveWallpapers.qml'),'restore'),state);state.restore();
 assert.equal(sent[0]?.action,'prepare');assert.equal(state.restoring,true);
});
test('disconnected live layers suspend independently and return on reconnect',()=>{
 const screens=[{name:'A'}],state=vm.createContext({Quickshell:{screens}});
 vm.runInContext(['outputConnected','renderableLive'].map(name=>extract(qml('Wallpapers.qml'),name)).join('\n'),state);
 state.liveLayers=doc=>doc.live.layers;
 const doc={live:{layers:[{id:'single',outputs:['A'],visibleOutputs:['A']},{id:'span',outputs:['A','B'],visibleOutputs:['A','B']}]}};
 assert.deepEqual(Array.from(state.renderableLive(doc).layers,x=>x.id),['single']);
 screens.push({name:'B'});assert.deepEqual(Array.from(state.renderableLive(doc).layers,x=>x.id),['single','span']);
});
test('logical output roles follow primary changes and a disconnected secondary',()=>{
 const state=vm.createContext({});vm.runInContext(qml('WidgetLayoutState.js'),state);
 const screens=[{name:'A',x:0},{name:'B',x:-1920}];
 assert.equal(state.resolveOutput('secondary',screens,'A'),'B');
 assert.equal(state.resolveOutput('secondary',screens,'B'),'A');
 assert.equal(state.resolveOutput('primary',screens,'missing'),'A');
 assert.equal(state.resolveOutput('secondary',screens.slice(0,1),'A'),null);
 assert.equal(state.roleForOutput('B',screens,'A'),'secondary');
 assert.equal(state.roleForOutput('C',[...screens,{name:'C',x:1920}],'A'),'C');
});
function windowActions(){
 const source=readFileSync(new URL('../config/shojiwm/src/window-manager.ts',import.meta.url),'utf8');
 const methods=['maximizeFocusedWindow','restoreFocusedWindow','toggleShowDesktop'].map(name=>extract(source,name,'  public '));
 return vm.runInNewContext(stripTypeScriptTypes('class Actions {\n'+methods.join('\n')+'\n}\nActions'),{WINDOW_STATE_MINIMIZED:'minimized',WINDOW_STATE_MAXIMIZED:'maximized',read:v=>typeof v==='function'?v():v,isMateEngineWindow:w=>w.pet});
}
test('show desktop restores its own surviving windows and original focus',()=>{
 const Actions=windowActions(),actions=new Actions(),hidden=new Set(['already-minimized']);
 const focused={id:'focused'},minimized={id:'already-minimized'},pet={id:'pet',pet:true},inactive={id:'inactive'},closed={id:'closed'};
 const active=[focused,minimized,pet,closed];
 for(const w of [...active,inactive])Object.assign(w,{state:{minimized:()=>hidden.has(w.id)},isFocused:()=>w===focused,minimize:()=>hidden.add(w.id),focus:()=>{actions.focused=w.id;}});
 actions.workspaces=new Map([[1,{isActive:()=>true,listWindows:()=>active}],[2,{isActive:()=>false,listWindows:()=>[inactive]}]]);
 actions.findWindowById=id=>[...active,inactive].find(w=>w.id===id);
 actions.onWindowMinimizeRequest=({window,minimized})=>{assert.equal(minimized,false);hidden.delete(window.id);};
 actions.toggleShowDesktop();assert.deepEqual([...hidden].sort(),['already-minimized','closed','focused']);
 active.splice(active.indexOf(closed),1);actions.toggleShowDesktop();
 assert.equal(hidden.has('already-minimized'),true);assert.equal(hidden.has('focused'),false);assert.equal(actions.focused,'focused');
});
test('maximize and restore/minimize keep one-way semantics',()=>{
 const Actions=windowActions(),actions=new Actions();let maximized=false,minimized=false;
 const window={isResizable:true,state:{maximized:()=>maximized},maximize:()=>{maximized=true;},unmaximize:()=>{maximized=false;},minimize:()=>{minimized=true;}};
 actions.workspaces=new Map([[1,{focusedWindow:()=>window}]]);
 actions.maximizeFocusedWindow();actions.maximizeFocusedWindow();assert.equal(maximized,true);
 actions.restoreFocusedWindow();assert.equal(maximized,false);assert.equal(minimized,false);
 actions.restoreFocusedWindow();assert.equal(minimized,true);
});

test('Claude collection refuses direct execution without opt-in',()=>{
 for(const flag of [undefined,'0']){
  const directory=mkdtempSync(join(tmpdir(),'tab-stack-claude-gate-'));
  try{
   const env={...process.env,CLAUDE_CONFIG_DIR:join(directory,'credentials'),XDG_CACHE_HOME:join(directory,'cache')};
   delete env.SHOJI_ENABLE_LIMITS;if(flag!==undefined)env.SHOJI_ENABLE_LIMITS=flag;
   const result=spawnSync(process.execPath,[new URL('ai-limits.mjs',shell).pathname,'--providers=claude'],{env,encoding:'utf8',timeout:2000});
   assert.equal(result.status,1);assert.equal(existsSync(join(directory,'cache')),false);
  }finally{rmSync(directory,{recursive:true,force:true});}
 }
});
