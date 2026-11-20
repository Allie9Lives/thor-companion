import fs from 'node:fs/promises';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const code=await fs.readFile(new URL('../../assets/web-ops/app.js',import.meta.url),'utf8');
const elements=new Map(),events={},pending=[];
const element=id=>{if(!elements.has(id))elements.set(id,{value:'',dataset:{},style:{setProperty(){}},classList:{toggle(){},add(){},remove(){},contains(){return false;}},addEventListener(){},append(){},replaceChildren(){},attributes:{},removeAttribute(name){delete this.attributes[name];},setAttribute(name,value){this.attributes[name]=String(value);},toggleAttribute(){},textContent:''});return elements.get(id);};
const document={hidden:false,documentElement:{dataset:{}},body:{dataset:{},append(){}},getElementById:element,querySelector:()=>({content:'clearPurple'}),querySelectorAll:()=>[],createElement:()=>element('node'+elements.size),createElementNS:()=>element('node'+elements.size),addEventListener:(name,callback)=>events[name]=callback};
const context={document,window:{addEventListener(){},dispatchEvent(){}},Event:class{},CustomEvent:class{},localStorage:{getItem:()=>null,setItem(){}},location:{hash:'',origin:'https://192.168.1.2:47184',pathname:'/',search:''},history:{replaceState(){}},fetch:path=>path==='/api/state'?new Promise((resolve,reject)=>pending.push({resolve,reject})):Promise.resolve({ok:true,status:200,json:async()=>({theme:'clearPurple'})}),AbortController,AbortSignal,Date,setTimeout:()=>1,clearTimeout(){},setInterval(){},clearInterval(){},performance:{now:()=>context.now},queueMicrotask(){},matchMedia:()=>({matches:true}),crypto:{randomUUID:()=>''},renderCount:0,now:0};
vm.createContext(context);vm.runInContext(code,context);vm.runInContext('render=()=>renderCount++;showDashboard("test")',context);
assert.equal(element('sync-brightness').checked,true);assert.equal(element('sync-volume').checked,true);
async function resumeWithOldResult(status){const old=pending.length-1;document.hidden=true;events.visibilitychange();document.hidden=false;events.visibilitychange();const fresh=pending.length-1;pending[fresh].resolve({ok:true,status:200,json:async()=>({})});await new Promise(r=>setTimeout(r,0));if(status)pending[old].resolve({ok:false,status,json:async()=>({error:'Old session expired'})});else pending[old].reject(new TypeError('Suspended request failed'));await new Promise(r=>setTimeout(r,0));assert.equal(vm.runInContext('active',context),true);assert.equal(element('error').textContent,'');assert.equal(element('connection').dataset.state,'connected');}
await resumeWithOldResult(0);vm.runInContext('poll()',context);await resumeWithOldResult(401);assert.equal(context.renderCount,2);
console.log('PWA stale-network and stale-401 recovery passed; sync defaults passed.');
vm.runInContext(`renderActivity({lid:false,apps:[{d:0,p:'test.top',name:'Top game',cpu:8},{d:4,p:'test.bottom',name:'Bottom game',cpu:3}]})`,context);
for(const prefix of ['', 'drawer-']){
 assert.equal(element(`${prefix}focused-top-name`).textContent,'Top game');
 assert.equal(element(`${prefix}focused-bottom-name`).textContent,'Bottom game');
 assert.equal(element(`${prefix}lid`).textContent,'Lid open');
}
vm.runInContext(`recordingUI({state:'recording',mode:2,elapsed_ms:8000,max_seconds:180})`,context);
assert.equal(element('record-duration').textContent,'Recording both screens · 0:08 / 3:00');
context.now=2000;vm.runInContext('updateRecordingDuration()',context);
assert.equal(element('record-duration').textContent,'Recording both screens · 0:10 / 3:00');
vm.runInContext(`recordingUI({state:'ready',mode:2,elapsed_ms:90000,tracks:[{screen:0,offset_ms:100,duration_ms:5000},{screen:1,offset_ms:400,duration_ms:5200}]})`,context);
assert.equal(element('record-duration').textContent,'Duration · 0:05');
context.now=60000;vm.runInContext('updateRecordingDuration()',context);
assert.equal(element('record-duration').textContent,'Duration · 0:05');
vm.runInContext(`recordingUI({state:'idle'})`,context);
assert.equal(element('record-duration').hidden,true);
console.log('Overview and App drawer activity match; recording timer and finalized duration passed.');

vm.runInContext(`renderPerformance({cpu_pct:24,cpu_window_ms:30000,gpu_pct:50,ram_free_bytes:4},{ram_total_bytes:16})`,context);
assert.equal(element('cpu-bar').hidden,false);assert.equal(element('cpu-bar-fill').style.transform,'scaleX(0.24)');
assert.equal(element('gpu-bar-fill').style.transform,'scaleX(0.5)');assert.equal(element('ram-bar-fill').style.transform,'scaleX(0.75)');
vm.runInContext(`renderPerformance({cpu_pct:24,cpu_window_ms:100,gpu_pct:null,ram_free_bytes:4},{ram_total_bytes:0})`,context);
for(const key of ['cpu','gpu','ram']){assert.equal(element(`${key}-bar`).hidden,true);assert.equal(element(key).textContent,'Unavailable');}
console.log('Live usage bars and unavailable readings passed.');

vm.runInContext(`renderHardware({device_name:"Named device",variant:'Max',storage_capacity_bytes:1000000000000,ufs_version:'4.0',cpu_name:'Snapdragon 8 Gen 2',gpu_name:'Adreno 740',build:'Device firmware'})`,context);
assert.equal(element('device-name').textContent,'Named device');assert.equal(element('device-model').textContent,'AYN Thor Max');assert.equal(element('device-capacity').textContent,'1 TB');assert.equal(element('device-ufs').textContent,'UFS 4.0');assert.equal(element('device-build').textContent,'Device firmware');
vm.runInContext(`renderHardware({model:'Device',storage_capacity_bytes:null})`,context);
assert.equal(element('device-model').textContent,'Device');assert.equal(element('device-capacity').textContent,'Unavailable');assert.equal(element('device-ufs').textContent,'Unknown');
console.log('Hardware summary and unavailable configuration passed.');

vm.runInContext(`renderStorage({free_bytes:25,sd_state:'read_only',sd_total_bytes:100,sd_free_bytes:50},{data_total_bytes:100,ufs_version:'4.0'})`,context);
assert.equal(element('storage-bar-fill').style.transform,'scaleX(0.75)');assert.equal(element('sd-bar-fill').style.transform,'scaleX(0.5)');
assert.ok(element('storage-caption').textContent.includes('75% used'));assert.ok(element('sd-caption').textContent.includes('Read only'));
vm.runInContext(`renderStorage({free_bytes:null,sd_state:'not_present'},{data_total_bytes:0})`,context);
assert.equal(element('storage-bar').hidden,true);assert.equal(element('storage-free-label').hidden,true);assert.equal(element('sd').textContent,'No microSD card detected');assert.equal(element('sd-bar').hidden,true);assert.equal(element('sd-caption').textContent,'');
console.log('Internal and read-only/missing microSD capacity handling passed.');

vm.runInContext(`applyControls({settings:true,power_control:true,find:1,vt:20,vb:20})`,context);
assert.equal(element('find-label').textContent,'Stop sound');assert.equal(element('find-symbol').attributes.href,'#ui-mute');assert.equal(element('vt').disabled,true);
vm.runInContext(`applyControls({settings:true,power_control:true,find:0,vt:20,vb:20})`,context);
assert.equal(element('find-label').textContent,'Find my Thor');assert.equal(element('find-symbol').attributes.href,'#ui-volume');assert.equal(element('vt').disabled,false);
console.log('Find button icon and volume lock survive control refreshes.');
