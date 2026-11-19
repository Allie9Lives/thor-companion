'use strict';
// Runs before the stylesheet and body, so the first paint uses the saved theme.
(()=>{
 const themes=['dark','light','clearPurple','rainbow'];
 let host=document.querySelector('meta[name=thor-host-theme]')?.content,choice='host';
 if(!themes.includes(host))host='dark';
 try{choice=localStorage.getItem('thor-web-theme')||'host';}catch{}
 const resolved=themes.includes(choice)?choice:host;
 document.documentElement.dataset.theme=resolved;
 const color=document.querySelector('meta[name=theme-color]');
 if(color)color.content=({dark:'#111113',light:'#f2f2f5',clearPurple:'#1d1825',rainbow:'#c6c4c0'})[resolved];
})();
