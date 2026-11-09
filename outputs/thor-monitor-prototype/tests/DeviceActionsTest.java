package com.alan.thormonitor;
public class DeviceActionsTest {
 public static void main(String[] args){
  if(Math.abs(LocatorEnvelope.amplitude(0)-0.035)>0.0001 || LocatorEnvelope.amplitude(10000)!=1 || LocatorEnvelope.amplitude(60000)!=1)throw new AssertionError("Ramp endpoints");
  if(LocatorEnvelope.amplitude(5000)>=1||LocatorEnvelope.amplitude(-1)!=LocatorEnvelope.amplitude(0))throw new AssertionError("Ramp timing and clamping");
  float previous=0;for(int ms=0;ms<=10000;ms+=100){float v=LocatorEnvelope.amplitude(ms);if(v<previous||v>1)throw new AssertionError("Ramp monotonicity");previous=v;}
  if(!DevicePower.command(0)[2].equals("223") || !DevicePower.command(1)[2].equals("reboot") || !DevicePower.command(2)[2].equals("shutdown"))throw new AssertionError("Power allowlist");
  if(!DevicePower.command(3)[2].equals("224"))throw new AssertionError("Wake command");
  try{DevicePower.command(4);throw new AssertionError("Unsupported action allowed");}catch(IllegalArgumentException expected){}
  float fade=1;for(int ms=0;ms<=240;ms+=10){float v=LocatorEnvelope.fadeOut(1,ms);if(v>fade||v<0)throw new AssertionError("Fade monotonicity");fade=v;}if(LocatorEnvelope.fadeOut(1,0)!=1||Math.abs(LocatorEnvelope.fadeOut(1,220))>.00001)throw new AssertionError("Fade endpoints");
  System.out.println("Locator envelope and fixed power allowlist tests passed.");
 }
}
