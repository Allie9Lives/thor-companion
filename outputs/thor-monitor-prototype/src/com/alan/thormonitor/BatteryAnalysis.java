package com.alan.thormonitor;
import java.util.*;
/** Uses measured contiguous history only. Shared units: milliseconds, percentage points. */
final class BatteryAnalysis {
 static final class Summary {double drain;long power,screen,coverage;Double peak;final Map<Long,Double> hours=new TreeMap<>();}
 static Summary summary(List<BatterySample> points,long start,long end){
  Summary out=new Summary();for(BatterySample p:points)if(p.time>=start&&p.time<=end&&p.temperature!=null)out.peak=out.peak==null?p.temperature:Math.max(out.peak,p.temperature);
  for(int i=1;i<points.size();i++){BatterySample a=points.get(i-1),b=points.get(i);long delta=b.time-a.time;if(delta<=0||delta>600000)continue;long from=Math.max(start,a.time),to=Math.min(end,b.time),duration=to-from;if(duration<=0)continue;
   out.coverage+=duration;if(a.plugged)out.power+=duration;if(a.screenOn)out.screen+=duration;
   if(!a.plugged&&!b.plugged&&a.level>b.level){double drop=(a.level-b.level)*duration/delta;out.drain+=drop;long cursor=from;while(cursor<to){Calendar clock=Calendar.getInstance();clock.setTimeInMillis(cursor);long hour=cursor-(clock.get(Calendar.MINUTE)*60000L+clock.get(Calendar.SECOND)*1000L+clock.get(Calendar.MILLISECOND)),stop=Math.min(to,hour+3600000);out.hours.put(hour,out.hours.getOrDefault(hour,0.0)+drop*(stop-cursor)/duration);cursor=stop;}}
  }return out;
 }
 static final class Runtime {final String label,detail;final Long minMinutes,maxMinutes;Runtime(String l,String d){this(l,d,null,null);}Runtime(String l,String d,Long a,Long b){label=l;detail=d;minMinutes=a;maxMinutes=b;}}
 static Runtime runtime(List<BatterySample> history,BatterySample current){
  if(current==null)return new Runtime("Waiting for readings","Battery readings will appear here.");
  if(current.plugged)return new Runtime("External power connected","An estimate needs measured unplugged use.");
  if(current.level<=0)return new Runtime("Battery empty","Connect the Thor to power.");
  TreeMap<Long,BatterySample> index=new TreeMap<>();for(BatterySample p:history)if(p.time<=current.time&&p.time>=current.time-7200000)index.put(p.time,p);index.put(current.time,current);
  List<BatterySample> sorted=new ArrayList<>(index.values()),segment=new ArrayList<>();segment.add(current);
  for(int i=sorted.size()-2;i>=0;i--){BatterySample a=sorted.get(i),b=segment.get(0);long gap=b.time-a.time;if(a.plugged||gap<=0||gap>600000||b.level-a.level>1)break;segment.add(0,a);}
  long span=current.time-segment.get(0).time;double drop=segment.get(0).level-current.level;
  if(segment.size()<4||span<900000||drop<2)return new Runtime("Collecting usage history","Needs 15 minutes unplugged and a 2% drop. Charging and recording gaps start a new segment.");
  double overall=drop/(span/3600000.0);if(!Double.isFinite(overall)||overall<.5)return new Runtime("Drain is too low to estimate","More measured battery use is needed.");
  double recent=overall;BatterySample first=current;for(BatterySample p:segment)if(p.time>=current.time-1800000){first=p;break;}
  long recentSpan=current.time-first.time;double recentDrop=first.level-current.level;if(recentSpan>=900000&&recentDrop>=1)recent=recentDrop/(recentSpan/3600000.0);
  if(Math.max(overall,recent)/Math.min(overall,recent)>4)return new Runtime("Usage is changing","Wait for a steadier recent usage pattern.");
  double fast=Math.max(overall,recent)*1.35,slow=Math.max(.5,Math.min(overall,recent)*.75);long low=Math.max(1,(long)Math.floor(current.level/fast*12)*5),high=Math.max(low,(long)Math.ceil(current.level/slow*12)*5);
  if(low>10080)return new Runtime("Drain is too low to estimate","Recent use is too light for a useful prediction.");
  String label=low>=1440?"Over 24 h":high<=5?"Under 5 min":low==high?"About "+time(low):time(low)+" – "+time(high);
  return new Runtime(label,"Based on "+span/60000+" minutes unplugged. Workload, brightness and fan settings can change the result.",low,high);
 }
 static String time(long minutes){return minutes<60?minutes+" min":minutes%60==0?minutes/60+" h":minutes/60+" h "+minutes%60+" min";}
}
