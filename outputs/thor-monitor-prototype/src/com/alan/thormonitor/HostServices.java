package com.alan.thormonitor;
import android.content.Context;import org.json.*;
/** Status is compact enough to accompany every Bluetooth controls reply. */
final class HostServices {
 static int bits(Context c){return (MonitorService.running&&!MonitorService.paused(c)?1:0)|(WebOps.running()?2:0)|(FtpAccess.running()?4:0)|(WebOps.configured(c)?8:0)|(MonitorService.paused(c)?16:0);}
 static JSONObject command(Context c,String action,String id)throws Exception{
  if(action.equals("web_ops_start")){
   if(!WebOps.configured(c))throw new IllegalStateException("Set an owner login in Thor Monitor → Settings → Web Ops first.");
   WebOps.prefs(c).edit().putBoolean("enabled",true).apply();WebOps.refresh(c);
   if(!WebOps.running())throw new IllegalStateException(WebOps.error.isEmpty()?"Web Ops needs a local network or private VPN address.":WebOps.error);
  }else if(action.equals("web_ops_stop")){WebOps.prefs(c).edit().putBoolean("enabled",false).apply();WebOps.stop();}
  else if(action.equals("monitor_pause")||action.equals("monitor_resume")){MonitorService.pauseReadings(c,action.equals("monitor_pause"));return new JSONObject().put("ack",id).put("error","").put("svc",bits(c));}
  else if(!action.equals("web_ops_status"))throw new IllegalArgumentException("Unknown service action");
  JSONArray urls=new JSONArray();if(WebOps.running())for(String url:WebOps.urls().split("\\s+"))if(!url.isEmpty()&&urls.length()<3)urls.put(url);
  return new JSONObject().put("ack",id).put("error","").put("svc",bits(c)).put("urls",urls);
 }
}
