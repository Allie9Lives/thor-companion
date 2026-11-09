package com.alan.thormonitor;
final class BatterySample {
 final long time;final double level;final boolean plugged,screenOn;final Double temperature;
 BatterySample(long t,double p,boolean b,boolean s,Double temp){time=t;level=p;plugged=b;screenOn=s;temperature=temp;}
}
