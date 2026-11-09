package com.alan.thormonitor;
import java.util.*;
public class RestPolicyTest {
 public static void main(String[] args){
  if(!RestPolicy.pause(0,true,true,1260,1260,360,10800000,10800000))throw new AssertionError("Night start");
  if(!RestPolicy.pause(0,true,true,359,1260,360,10800000,10800000)||RestPolicy.pause(0,true,true,360,1260,360,10800000,10800000))throw new AssertionError("Morning boundary");
  if(RestPolicy.pause(0,true,false,1300,1260,360,10800000,10800000)||RestPolicy.pause(0,false,true,1300,1260,360,10800000,10800000)||RestPolicy.pause(0,true,true,1300,1260,360,10799999,10800000))throw new AssertionError("Trust, active use or dwell guard");
  if(RestPolicy.pause(1,true,true,1300,1260,360,10800000,10800000)||!RestPolicy.pause(2,false,false,600,1260,360,0,10800000))throw new AssertionError("Always-on and passive modes");
  if(RestPolicy.shouldPause(false,true,true,0,true,true,1300,1260,360,10800000,10800000))throw new AssertionError("Plugged-in override");
  if(!RestPolicy.shouldPause(false,false,true,0,true,true,1300,1260,360,10800000,10800000))throw new AssertionError("Unplugging reapplies dwell");
  if(!RestPolicy.shouldPause(false,true,false,0,true,true,1300,1260,360,10800000,10800000))throw new AssertionError("Optional override must default off");
  if(!RestPolicy.shouldPause(true,true,true,0,true,true,1300,1260,360,0,10800000))throw new AssertionError("Manual sleep takes precedence");
  if(RestPolicy.shouldPause(false,true,true,2,true,false,600,1260,360,0,10800000))throw new AssertionError("Powered passive override");
  if(RestPolicy.pause(0,true,true,1300,1260,360,59*60000,60*60000)||!RestPolicy.pause(0,true,true,1300,1260,360,60*60000,60*60000))throw new AssertionError("Custom 60-minute delay");
  TimeZone old=TimeZone.getDefault();try{TimeZone.setDefault(TimeZone.getTimeZone("America/New_York"));Calendar c=Calendar.getInstance();c.clear();c.set(2026,Calendar.MARCH,7,6,0,0);long now=c.getTimeInMillis(),next=RestPolicy.next(now,360);if(next-now!=23L*3600000)throw new AssertionError("DST morning restore");c.setTimeInMillis(next);if(c.get(Calendar.HOUR_OF_DAY)!=6)throw new AssertionError("Local clock restore");}finally{TimeZone.setDefault(old);}
  System.out.println("Overnight boundaries, trusted Wi-Fi, 3-hour dwell, modes, charger override, custom delay and DST restore passed.");
 }
}
