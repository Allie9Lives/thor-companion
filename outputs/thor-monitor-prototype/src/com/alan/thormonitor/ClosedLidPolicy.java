package com.alan.thormonitor;
import java.util.ArrayDeque;
/** Monotonic observations, a rolling drain window and consecutive load; unknown lid never counts. */
final class ClosedLidPolicy {
 long closedAt=-1,lastWarning=-1,lastObservation=-1;int streak;
 private static final class Point{final long time;final double level;Point(long t,double p){time=t;level=p;}}
 private final ArrayDeque<Point> history=new ArrayDeque<>();
 boolean observe(long now,Boolean closed,double cpu,double gpu,double battery,boolean plugged){
  if(lastObservation>=0&&(now<lastObservation||now-lastObservation>120000)){closedAt=-1;streak=0;history.clear();}
  lastObservation=now;
  if(!Boolean.TRUE.equals(closed)){closedAt=-1;streak=0;history.clear();return false;}
  if(closedAt<0)closedAt=now;
  if(plugged||!Double.isFinite(battery))history.clear();
  else{history.addLast(new Point(now,battery));while(!history.isEmpty()&&history.peekFirst().time<now-600000)history.removeFirst();}
  boolean drain=!history.isEmpty()&&history.peekFirst().level-battery>=3;
  if(cpu>=12.5||gpu>=30||drain)streak++;else streak=0;
  if(now-closedAt>=600000&&streak>=3&&(lastWarning<0||now-lastWarning>=1800000)){lastWarning=now;return true;}return false;
 }
 long seconds(long now){return closedAt<0?0:Math.max(0,(now-closedAt)/1000);}
}
