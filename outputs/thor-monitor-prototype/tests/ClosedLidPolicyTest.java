package com.alan.thormonitor;
public final class ClosedLidPolicyTest {
 static void check(boolean ok){if(!ok)throw new AssertionError();}
 public static void main(String[] args){
  ClosedLidPolicy p=new ClosedLidPolicy();for(int i=0;i<20;i++)check(!p.observe(i*30000L,true,20,0,100,false));check(p.observe(600000,true,20,0,100,false));check(!p.observe(630000,true,20,0,100,false));
  p.observe(650000,false,100,100,90,false);check(p.seconds(660000)==0);check(!p.observe(2000000,null,100,100,80,false));check(p.seconds(2100000)==0);
  p=new ClosedLidPolicy();for(int i=0;i<20;i++)check(!p.observe(i*30000L,true,0,0,i<18?100:97,false));check(p.observe(600000,true,0,0,97,false));
  p=new ClosedLidPolicy();for(int i=0;i<121;i++)check(!p.observe(i*30000L,true,0,0,100-i/20,false)); // Normal 1 point/10min is never a fast-drain warning.
  p=new ClosedLidPolicy();for(int i=0;i<20;i++)check(!p.observe(i*30000L,true,100,0,100,true));check(!p.observe(900000,true,100,0,100,true));check(p.seconds(900000)==0); // Observation gap resets closed-duration evidence.
  System.out.println("Closed-lid gate, sustained load, unknown switch, rolling drain, normal standby and observation gap tests passed");
 }
}
