package com.alan.thormonitor;
public class PhoneRepairGateTest {
 public static void main(String[] args){
  PhoneRepairGate gate=new PhoneRepairGate();
  if(gate.contains("unknown",100))throw new AssertionError("Unrequested phone eligible");
  if(!gate.record("phone",100)||gate.record("phone",200))throw new AssertionError("Duplicate request logging");
  if(!gate.contains("phone",300))throw new AssertionError("Recent request missing");
  if(gate.contains("phone",PhoneRepairGate.WINDOW_MS+201))throw new AssertionError("Expired request eligible");
  for(int i=0;i<9;i++)gate.record("phone"+i,400000);
  if(gate.contains("phone0",400001)||!gate.contains("phone8",400001))throw new AssertionError("Unbounded candidates");
  gate.clear();if(gate.contains("phone8",400001))throw new AssertionError("Approval failed to invalidate candidates");
  gate.record("later",500000);if(gate.contains("later",1))throw new AssertionError("Clock rollback accepted");
  if(LocatorEnvelope.amplitude(0)<.8||LocatorEnvelope.amplitude(120)!=1f||LocatorEnvelope.amplitude(10000)!=1f)throw new AssertionError("Alarm must start high and reach full quickly");
  if(LocatorEnvelope.fadeOut(1f,0)!=1f||LocatorEnvelope.fadeOut(1f,220)!=0f)throw new AssertionError("Dismissal must fade to silence");
  System.out.println("Repair candidate expiry, bounds, invalidation and loud locator envelope passed.");
 }
}
