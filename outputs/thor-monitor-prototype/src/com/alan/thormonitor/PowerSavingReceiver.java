package com.alan.thormonitor;
import android.content.*;
public final class PowerSavingReceiver extends BroadcastReceiver {
 public void onReceive(Context c,Intent i){
  android.content.SharedPreferences p=c.getSharedPreferences("monitor",0);
  if(!p.getBoolean("monitor_wanted",false))return;
  String action=i.getAction();boolean alarm="com.alan.thormonitor.REST_ALARM".equals(action);
  // A morning alarm restores keep-alive without lighting either screen.
  if(alarm&&i.getBooleanExtra("restore",false))p.edit().putBoolean("rest_manual",false).putLong("rest_resume_token",System.currentTimeMillis()).apply();
  try{c.startForegroundService(new Intent(c,MonitorService.class).setAction("REST_EVALUATE").putExtra("always_on",p.getBoolean("always_on",true)));}catch(Exception ignored){}
 }
}
