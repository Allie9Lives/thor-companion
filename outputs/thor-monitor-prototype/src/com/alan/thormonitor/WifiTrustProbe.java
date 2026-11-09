package com.alan.thormonitor;
import org.json.*;import java.util.regex.*;import java.security.*;import java.nio.charset.StandardCharsets;
/** Fixed read-only shell probe; no network configuration or VPN changes. */
final class WifiTrustProbe {
 static JSONObject sample()throws Exception{
  String status=ActivityProbe.command("/system/bin/cmd","wifi","status");
  Matcher ssid=Pattern.compile("WifiInfo: SSID: (.*?), BSSID:").matcher(status),security=Pattern.compile("Security type: ([0-9]+)").matcher(status);
  if(!status.contains("Supplicant state: COMPLETED")||!ssid.find()||!security.find())return new JSONObject().put("ok",false);
  String name=ssid.group(1);if(name.equals("<unknown ssid>")||name.length()>128)return new JSONObject().put("ok",false);
  String identity=name+"\n"+security.group(1);StringBuilder key=new StringBuilder();for(byte b:MessageDigest.getInstance("SHA-256").digest(identity.getBytes(StandardCharsets.UTF_8)))key.append(String.format(java.util.Locale.ROOT,"%02x",b&255));
  if(name.startsWith("\"")&&name.endsWith("\""))name=name.substring(1,name.length()-1);
  return new JSONObject().put("ok",true).put("name",name).put("key",key.toString());
 }
}
