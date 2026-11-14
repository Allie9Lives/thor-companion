package com.alan.thormonitor;
import android.app.*;import android.content.*;import android.os.*;
/** Optional task-dismissal safety net; never overrides a deliberate Stop or Android force-stop. */
public final class ServiceRecovery extends BroadcastReceiver {
 static boolean wanted(Context c){android.content.SharedPreferences p=c.getSharedPreferences("monitor",0);return p.getBoolean("monitor_wanted",false)&&p.getBoolean("recover_dismissal",true);}
 static void cancel(Context c){PendingIntent pending=PendingIntent.getBroadcast(c,41,new Intent(c,ServiceRecovery.class),PendingIntent.FLAG_NO_CREATE|PendingIntent.FLAG_IMMUTABLE);if(pending!=null)c.getSystemService(AlarmManager.class).cancel(pending);}
 static void schedule(Context c){if(!wanted(c))return;PendingIntent pending=PendingIntent.getBroadcast(c,41,new Intent(c,ServiceRecovery.class),PendingIntent.FLAG_IMMUTABLE|PendingIntent.FLAG_UPDATE_CURRENT);c.getSystemService(AlarmManager.class).setAndAllowWhileIdle(AlarmManager.ELAPSED_REALTIME_WAKEUP,SystemClock.elapsedRealtime()+5000,pending);}
 @Override public void onReceive(Context c,Intent i){if(MonitorService.running||!wanted(c))return;try{c.startForegroundService(new Intent(c,MonitorService.class).putExtra("always_on",c.getSharedPreferences("monitor",0).getBoolean("always_on",false)));}catch(Exception e){try{Telemetry.log(c,"service_recovery_delayed",new org.json.JSONObject().put("reason",e.getClass().getSimpleName()));}catch(Exception ignored){}}}
}
