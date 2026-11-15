// No API/data caching, interception, push server or background wake timer.
self.addEventListener('install',()=>self.skipWaiting());
self.addEventListener('activate',event=>event.waitUntil(self.clients.claim()));
self.addEventListener('notificationclick',event=>{event.notification.close();event.waitUntil((async()=>{const tabs=await self.clients.matchAll({type:'window',includeUncontrolled:true});for(const tab of tabs)if(new URL(tab.url).origin===self.location.origin){await tab.focus();return;}await self.clients.openWindow('/');})());});
