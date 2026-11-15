package com.alan.thormonitor;
import android.content.*;import android.os.*;import android.app.*;import java.util.*;import org.json.*;
/** Explicit owner settings; Android permission grants still happen locally. */
final class WebSettings {
 static JSONObject read(Context c)throws Exception{
  SharedPreferences p=c.getSharedPreferences("monitor",0);JSONObject out=PowerSaving.snapshot(c);JSONArray networks=new JSONArray();for(String key:p.getStringSet("rest_trusted",Collections.emptySet()))networks.put(new JSONObject().put("id",key).put("name",p.getString("rest_name_"+key,"Trusted Wi-Fi")));
  out.put("trusted",networks).put("idle_minutes",WebOps.prefs(c).getInt("idle_minutes",30)).put("version",HostUpdates.installed(c)).put("addresses",new JSONArray(WebOps.urlList())).put("fingerprint",WebTls.fingerprint(c));
  out.put("ready",new JSONObject().put("monitoring",MonitorService.running).put("controls",new ThorControls(c).helperReady()).put("storage",WebFiles.roots(c).getJSONArray("roots").length()>0).put("keyboard",RemoteKeyboard.selected(c)).put("exact_alarm",c.getSystemService(AlarmManager.class).canScheduleExactAlarms()));return out;
 }
 static JSONObject save(Context c,JSONObject body)throws Exception{
  SharedPreferences p=c.getSharedPreferences("monitor",0);String action=body.getString("action");
  if(action.equals("battery")){
   int mode=integer(body,"mode",0,2),start=integer(body,"start",0,1439),end=integer(body,"end",0,1439),delay=integer(body,"delay",1,1440);if(start==end)throw new IllegalArgumentException("Start and restore times must differ");if(!(body.get("keep_plugged") instanceof Boolean))throw new IllegalArgumentException("Choose charger behavior");
   p.edit().putInt("rest_mode",mode).putInt("rest_start",start).putInt("rest_end",end).putInt("rest_delay",delay).putBoolean("rest_keep_plugged",body.getBoolean("keep_plugged")).putBoolean("always_on",true).commit();MonitorService.restChanged();
  }else if(action.equals("trust_current")){
   JSONObject network=PowerSaving.network(c);if(!network.optBoolean("ok"))throw new IllegalStateException("Connect the Thor to Wi-Fi and finish Controls recovery first");if(!network.optString("key").equals(body.optString("expected")))throw new IllegalStateException("Wi-Fi changed. Review the network and try again");Set<String> keys=new HashSet<>(p.getStringSet("rest_trusted",Collections.emptySet()));keys.add(network.getString("key"));p.edit().putStringSet("rest_trusted",keys).putString("rest_name_"+network.getString("key"),network.getString("name")).commit();MonitorService.restChanged();
  }else if(action.equals("remove_trusted")){
   String key=body.getString("id");Set<String> keys=new HashSet<>(p.getStringSet("rest_trusted",Collections.emptySet()));if(!keys.remove(key))throw new IllegalArgumentException("Network no longer listed");p.edit().putStringSet("rest_trusted",keys).remove("rest_name_"+key).commit();MonitorService.restChanged();
  }else if(action.equals("session_idle")){int minutes=integer(body,"minutes",15,120);WebOps.sessions.idleMinutes(minutes);WebOps.prefs(c).edit().putInt("idle_minutes",minutes).commit();}
  else throw new IllegalArgumentException("Unknown setting");return read(c);
 }
 static int integer(JSONObject j,String key,int min,int max)throws Exception{Object raw=j.get(key);if(!(raw instanceof Number))throw new IllegalArgumentException("Invalid "+key);double value=((Number)raw).doubleValue();if(!Double.isFinite(value)||value!=Math.rint(value)||value<min||value>max)throw new IllegalArgumentException("Invalid "+key);return (int)value;}
}
