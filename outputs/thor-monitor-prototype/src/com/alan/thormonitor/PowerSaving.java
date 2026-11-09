package com.alan.thormonitor;
import android.app.*;import android.content.*;import android.os.*;import org.json.*;import java.util.*;import android.net.*;import java.io.*;
/** Releases only this app's CPU lock. Never forces Android's global Doze state. */
final class PowerSaving {
 final Context app;final SharedPreferences prefs;long idleSince=-1,lastNetwork,manualUntil,lastAlarmAt;boolean lastAlarmExact;boolean suspended;JSONObject network=new JSONObject();
 PowerSaving(Context c){app=c;prefs=c.getSharedPreferences("monitor",0);if(!prefs.contains("rest_policy_version"))prefs.edit().putInt("rest_policy_version",1).putInt("rest_mode",0).putBoolean("always_on",true).apply();}
 int mode(){return prefs.getInt("rest_mode",0);}int start(){return prefs.getInt("rest_start",1260);}int end(){return prefs.getInt("rest_end",360);}int delay(){return prefs.getInt("rest_delay",180);}
 static String clock(int minute){return String.format(Locale.getDefault(),"%02d:%02d",minute/60,minute%60);}
 static JSONObject network(Context c){
  try(LocalSocket socket=new LocalSocket()){
   socket.connect(new LocalSocketAddress(ThorControls.socketName(c),LocalSocketAddress.Namespace.ABSTRACT));socket.setSoTimeout(4000);if(socket.getPeerCredentials().getUid()!=2000)throw new SecurityException();
   byte[] request="{\"set\":\"wifi_identity\",\"value\":0}".getBytes("UTF-8");DataOutputStream out=new DataOutputStream(socket.getOutputStream());out.writeShort(request.length);out.write(request);out.flush();DataInputStream in=new DataInputStream(socket.getInputStream());int size=in.readUnsignedShort();if(size>1024)throw new IOException();byte[] bytes=new byte[size];in.readFully(bytes);return new JSONObject(new String(bytes,"UTF-8"));
  }catch(Exception e){return new JSONObject();}
 }
 void invalidateNetwork(){lastNetwork=0;}
 boolean trusted(){long now=SystemClock.elapsedRealtime();if(lastNetwork==0||now-lastNetwork>=30000){network=network(app);lastNetwork=now;}return network.optBoolean("ok")&&prefs.getStringSet("rest_trusted",Collections.emptySet()).contains(network.optString("key"));}
 static boolean externalPower(Context c){Intent battery=c.registerReceiver(null,new IntentFilter(Intent.ACTION_BATTERY_CHANGED));return battery!=null&&battery.getIntExtra(BatteryManager.EXTRA_PLUGGED,0)!=0;}
 boolean evaluate(boolean interactive,Boolean closed){
  long elapsed=SystemClock.elapsedRealtime(),now=System.currentTimeMillis();boolean idle=!interactive;
  if(!idle){idleSince=-1;if(elapsed>manualUntil&&prefs.getBoolean("rest_manual",false))prefs.edit().putBoolean("rest_manual",false).apply();}else if(idleSince<0||idleSince>elapsed)idleSince=elapsed;
  Calendar clock=Calendar.getInstance();int minute=clock.get(Calendar.HOUR_OF_DAY)*60+clock.get(Calendar.MINUTE);
  boolean powered=externalPower(app),keepPlugged=prefs.getBoolean("rest_keep_plugged",false);
  boolean pause=RestPolicy.shouldPause(prefs.getBoolean("rest_manual",false),powered,keepPlugged,mode(),idle,!(powered&&keepPlugged)&&mode()==0&&idle&&trusted(),minute,start(),end(),idleSince<0?0:elapsed-idleSince,delay()*60000L);
  if(pause!=suspended){suspended=pause;BatteryHistory.get(app).sleepEvent(now,pause?1:0);}
  prefs.edit().putBoolean("rest_suspended",pause).apply();
  schedule(now,idle?Math.max(0,delay()*60000L-(elapsed-idleSince)):-1);
  return pause;
 }
 void resume(){prefs.edit().putBoolean("rest_manual",false).apply();idleSince=SystemClock.elapsedRealtime();if(suspended){suspended=false;BatteryHistory.get(app).sleepEvent(System.currentTimeMillis(),0);}prefs.edit().putBoolean("rest_suspended",false).apply();}
 void manual(){manualUntil=SystemClock.elapsedRealtime()+5000;prefs.edit().putBoolean("rest_manual",true).apply();idleSince=SystemClock.elapsedRealtime();}
 boolean exact(){return app.getSystemService(AlarmManager.class).canScheduleExactAlarms();}
 void schedule(long now,long remaining){
  AlarmManager alarms=app.getSystemService(AlarmManager.class);PendingIntent pending=PendingIntent.getBroadcast(app,74,new Intent(app,PowerSavingReceiver.class).setAction("com.alan.thormonitor.REST_ALARM"),PendingIntent.FLAG_NO_CREATE|PendingIntent.FLAG_IMMUTABLE);
  if(!prefs.getBoolean("monitor_wanted",false)){if(pending!=null)alarms.cancel(pending);return;}
  long at=RestPolicy.next(now,end());if(mode()==0&&!suspended){at=Math.min(at,RestPolicy.next(now,start()));if(remaining>0)at=Math.min(at,now+remaining);}
  boolean precise=exact();if(at==lastAlarmAt&&precise==lastAlarmExact)return;lastAlarmAt=at;lastAlarmExact=precise;
  pending=PendingIntent.getBroadcast(app,74,new Intent(app,PowerSavingReceiver.class).setAction("com.alan.thormonitor.REST_ALARM").putExtra("restore",at==RestPolicy.next(now,end())),PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
  prefs.edit().putLong("rest_alarm_at",at).apply();
  try{if(exact())alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,at,pending);else alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,at,pending);}catch(SecurityException e){alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP,at,pending);}
 }
 static JSONObject snapshot(Context c)throws Exception{
  SharedPreferences p=c.getSharedPreferences("monitor",0);return new JSONObject().put("sleep_policy",true).put("sleep_mode",p.getInt("rest_mode",0)).put("sleep_start",p.getInt("rest_start",1260)).put("sleep_end",p.getInt("rest_end",360)).put("sleep_delay",p.getInt("rest_delay",180)).put("sleep_keep_plugged",p.getBoolean("rest_keep_plugged",false)).put("sleep_suspended",p.getBoolean("rest_suspended",false)).put("sleep_exact",c.getSystemService(AlarmManager.class).canScheduleExactAlarms()).put("sleep_restore_at",RestPolicy.next(System.currentTimeMillis(),p.getInt("rest_end",360)));
 }
}
