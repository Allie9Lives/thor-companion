package com.alan.thormonitor;
import java.util.*;
/** Local civil-time window. Calendar resolves timezone and daylight-saving changes. */
final class RestPolicy {
 static boolean inside(int minute,int start,int end){return start<end?minute>=start&&minute<end:start>end?(minute>=start||minute<end):false;}
 static long next(long now,int minute){Calendar c=Calendar.getInstance();c.setTimeInMillis(now);c.set(Calendar.HOUR_OF_DAY,minute/60);c.set(Calendar.MINUTE,minute%60);c.set(Calendar.SECOND,0);c.set(Calendar.MILLISECOND,0);if(c.getTimeInMillis()<=now)c.add(Calendar.DATE,1);return c.getTimeInMillis();}
 static boolean shouldPause(boolean manual,boolean powered,boolean keepPlugged,int mode,boolean idle,boolean trusted,int minute,int start,int end,long idleMs,long delayMs){return manual || (!(powered&&keepPlugged)&&pause(mode,idle,trusted,minute,start,end,idleMs,delayMs));}
 static boolean pause(int mode,boolean idle,boolean trusted,int minute,int start,int end,long idleMs,long delayMs){return mode==2 || (mode==0&&idle&&trusted&&inside(minute,start,end)&&idleMs>=delayMs);}
}
