package com.alan.thormonitor;
import java.util.*;
public class BatteryAnalysisTest {
 public static void main(String[] args){
  long now=1700000000000L;List<BatterySample> samples=new ArrayList<>();for(int ago=60;ago>=0;ago-=5)samples.add(new BatterySample(now-ago*60000L,68+ago*.2,false,true,35.0));
  BatteryAnalysis.Runtime r=BatteryAnalysis.runtime(samples,samples.get(samples.size()-1));if(r.minMinutes==null||r.minMinutes<240||r.maxMinutes>460)throw new AssertionError("Measured runtime range");
  if(BatteryAnalysis.runtime(samples,new BatterySample(now,68,true,true,null)).minMinutes!=null)throw new AssertionError("Charging prediction");
  List<BatterySample> gap=Arrays.asList(new BatterySample(now-3600000,80,false,false,null),new BatterySample(now,68,false,false,null));if(BatteryAnalysis.runtime(gap,gap.get(1)).minMinutes!=null)throw new AssertionError("Gap prediction");
  BatteryAnalysis.Summary s=BatteryAnalysis.summary(samples,now-3600000,now);if(Math.abs(s.drain-12)>.0001||s.screen!=3600000||s.coverage!=3600000||s.power!=0||s.peak!=35)throw new AssertionError("Observed summary");
  BatteryAnalysis.Summary missing=BatteryAnalysis.summary(gap,now-3600000,now);if(missing.drain!=0||missing.coverage!=0)throw new AssertionError("Invented gap usage");
  double sum=0;for(double value:s.hours.values())sum+=value;if(Math.abs(sum-s.drain)>.0001)throw new AssertionError("Hourly allocation");
  List<BatterySample> powered=Arrays.asList(new BatterySample(now-600000,70,true,true,34.0),new BatterySample(now-300000,71,true,false,35.0),new BatterySample(now,71,false,false,33.0));BatteryAnalysis.Summary charging=BatteryAnalysis.summary(powered,now-600000,now);if(charging.power!=600000||charging.screen!=300000||charging.drain!=0)throw new AssertionError("Power and sampled screen intervals");
  if(BatteryAnalysis.runtime(Collections.singletonList(samples.get(samples.size()-1)),samples.get(samples.size()-1)).minMinutes!=null)throw new AssertionError("Too little history");
  System.out.println("Battery history summary, gaps, charging and runtime checks passed.");
 }
}
