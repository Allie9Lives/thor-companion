import fs from 'node:fs/promises';
import vm from 'node:vm';
import assert from 'node:assert/strict';
const script=await fs.readFile(new URL('../../assets/web-ops/theme.js',import.meta.url),'utf8');
const html=await fs.readFile(new URL('../../assets/web-ops/index.html',import.meta.url),'utf8');
assert.ok(html.indexOf('<script src="/theme.js"></script>')<html.indexOf('<link rel="stylesheet"'));
assert.ok(html.includes('<html lang="en" data-theme="__THOR_THEME__">'));
// No body or app.js exists yet: the theme must already be correct.
for(const [host,saved,expected]of[['clearPurple',null,'clearPurple'],['dark','clearPurple','clearPurple'],['clearPurple','host','clearPurple'],['dark','light','light'],['light','rainbow','rainbow'],['clearPurple','invalid','clearPurple']]){
 const color={content:'#111113'},root={dataset:{theme:host}};
 vm.runInNewContext(script,{document:{documentElement:root,querySelector:selector=>selector.includes('thor-host-theme')?{content:host}:color},localStorage:{getItem:()=>saved}});
 assert.equal(root.dataset.theme,expected);
 if(expected==='clearPurple')assert.equal(color.content,'#1d1825');
}
const root={dataset:{}};
vm.runInNewContext(script,{document:{documentElement:root,querySelector:()=>({content:'clearPurple'})},localStorage:{getItem(){throw new Error('Storage blocked');}}});
assert.equal(root.dataset.theme,'clearPurple');
console.log('Pre-paint host theme, saved overrides, invalid settings and blocked storage passed.');
