/** Keep the app viewport fixed while preserving scrolling and control gestures. */
export function isMobileViewport(){return navigator.maxTouchPoints>0||matchMedia('(max-width: 760px)').matches;}
for(const name of ['gesturestart','gesturechange'])document.addEventListener(name,event=>{if(isMobileViewport())event.preventDefault();},{passive:false});
document.addEventListener('touchmove',event=>{if(isMobileViewport()&&event.touches.length>1)event.preventDefault();},{passive:false});
let lastTap=0,lastTarget=null;
document.addEventListener('touchend',event=>{const now=event.timeStamp,interactive=event.target.closest?.('button,a,input,select,textarea,label,summary,video');if(isMobileViewport()&&!interactive&&event.target===lastTarget&&now-lastTap<300)event.preventDefault();lastTap=now;lastTarget=event.target;},{passive:false});
