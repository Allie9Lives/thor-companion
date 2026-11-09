package com.alan.thormonitor;

import android.Manifest;
import android.content.*;
import android.content.pm.PackageManager;

public final class BootReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context c,Intent i) {
        if(!Intent.ACTION_BOOT_COMPLETED.equals(i.getAction()) && !Intent.ACTION_MY_PACKAGE_REPLACED.equals(i.getAction())) return;
        android.content.SharedPreferences prefs=c.getSharedPreferences("monitor",0);
        if(!prefs.getBoolean("monitor_wanted",false) || !prefs.getBoolean("start_on_boot",true)) return;
        if(c.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT)!=PackageManager.PERMISSION_GRANTED ||
           c.checkSelfPermission(Manifest.permission.BLUETOOTH_ADVERTISE)!=PackageManager.PERMISSION_GRANTED) return;
        try {
            c.startForegroundService(new Intent(c,MonitorService.class).putExtra("always_on",prefs.getBoolean("always_on",false)));
            Telemetry.log(c,"automatic_start",new org.json.JSONObject().put("reason",i.getAction()));
        } catch(Exception e) {
            try{Telemetry.log(c,"automatic_start_failed",new org.json.JSONObject().put("type",e.getClass().getSimpleName()));}catch(Exception ignored){}
        }
    }
}
