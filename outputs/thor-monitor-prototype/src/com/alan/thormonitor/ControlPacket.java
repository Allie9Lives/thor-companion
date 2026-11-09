package com.alan.thormonitor;
import org.json.*;import java.nio.charset.StandardCharsets;
/** ATT attributes are limited to 512 bytes, including every long-read fragment. */
final class ControlPacket {
 static byte[] bluetooth(JSONObject source)throws Exception{
  JSONObject j=new JSONObject(source.toString());
  if(j.optInt("v")==1&&j.has("settings")){
   // Host-only configuration and unused/obsolete hints stay in the full network
   // snapshot. Keep every setting and capability consumed by existing clients.
   for(String key:new String[]{"sleep_mode","sleep_start","sleep_delay","sleep_keep_plugged","wifi_screenshots","files","screenshots","keyboard_focused","brightness_error"})j.remove(key);
   String error=j.optString("error","");
   while(encoded(j).length>512&&!error.isEmpty()){error=error.substring(0,error.offsetByCodePoints(error.length(),-1));j.put("error",error);}
   if(encoded(j).length>512)j=new JSONObject().put("v",1).put("ack",j.optString("ack","")).put("error","Control status exceeds Bluetooth limit; use network controls.");
  }
  byte[] bytes=encoded(j);if(bytes.length>512)throw new IllegalStateException("Bluetooth reply exceeds attribute limit");return bytes;
 }
 private static byte[] encoded(JSONObject j){return j.toString().getBytes(StandardCharsets.UTF_8);}
}
