package com.alan.thormonitor;
import android.net.wifi.*;import android.os.*;import org.json.*;import java.util.*;import java.lang.reflect.*;import java.nio.charset.StandardCharsets;import java.util.regex.*;
/** Fixed Wi-Fi operations for the authenticated shell helper; credentials never enter argv or logs. */
final class WifiControls {
 static Object service()throws Exception{IBinder binder=(IBinder)Class.forName("android.os.ServiceManager").getMethod("getService",String.class).invoke(null,"wifi");return Class.forName("android.net.wifi.IWifiManager$Stub").getMethod("asInterface",IBinder.class).invoke(null,binder);}
 @SuppressWarnings("unchecked") static List<WifiConfiguration> configurations()throws Exception{Object s=service();Object slice=s.getClass().getMethod("getConfiguredNetworks",String.class,String.class,boolean.class).invoke(s,"com.android.shell",null,false);return (List<WifiConfiguration>)slice.getClass().getMethod("getList").invoke(slice);}
 static String name(String ssid){if(ssid==null)return "";if(ssid.startsWith("\"")&&ssid.endsWith("\"")){try{return new JSONArray("["+ssid+"]").getString(0);}catch(Exception e){return ssid.substring(1,ssid.length()-1);}}return ssid;}
 static String security(WifiConfiguration c){if(c.allowedKeyManagement.get(WifiConfiguration.KeyMgmt.SAE))return "wpa3";if(c.allowedKeyManagement.get(WifiConfiguration.KeyMgmt.WPA_PSK))return "wpa2";if(c.allowedKeyManagement.get(WifiConfiguration.KeyMgmt.WPA_EAP)||c.allowedKeyManagement.get(WifiConfiguration.KeyMgmt.IEEE8021X))return "enterprise";if(c.allowedKeyManagement.get(WifiConfiguration.KeyMgmt.OWE))return "owe";return "open";}
 static JSONObject status()throws Exception{
  String raw=ActivityProbe.command("/system/bin/cmd","wifi","status");JSONObject identity=WifiTrustProbe.parse(raw);Matcher id=Pattern.compile("Net ID: ([0-9]+)").matcher(raw);
  return new JSONObject().put("known",true).put("enabled",raw.startsWith("Wifi is enabled")).put("connected",identity.optBoolean("ok")).put("name",identity.optString("name","")).put("id",id.find()?Integer.parseInt(id.group(1)):-1);
 }
 static JSONArray saved()throws Exception{JSONArray list=new JSONArray();Set<Integer> ids=new HashSet<>();for(WifiConfiguration c:configurations())if(c.networkId>=0&&ids.add(c.networkId)){String ssid=name(c.SSID);if(!ssid.isEmpty())list.put(new JSONObject().put("id",c.networkId).put("n",ssid).put("s",security(c)));}return list;}
 @SuppressWarnings("unchecked") static JSONArray scan(boolean request)throws Exception{
  if(request)ActivityProbe.command("/system/bin/cmd","wifi","start-scan");Object s=service();List<ScanResult> scans=(List<ScanResult>)s.getClass().getMethod("getScanResults",String.class,String.class).invoke(s,"com.android.shell",null);
  scans.sort((a,b)->Integer.compare(b.level,a.level));JSONArray list=new JSONArray();Set<String> seen=new HashSet<>();
  for(ScanResult r:scans){String n=r.SSID,cap=r.capabilities==null?"":r.capabilities;String security=cap.contains("EAP")?"enterprise":cap.contains("SAE")?"wpa3":cap.contains("PSK")?"wpa2":cap.contains("OWE")?"owe":"open";if(n==null||n.isEmpty()||n.getBytes(StandardCharsets.UTF_8).length>32||!seen.add(n+"\n"+security))continue;list.put(new JSONObject().put("n",n).put("s",security).put("r",r.level));if(list.length()>=40)break;}return list;
 }
 static JSONObject connectSaved(int id)throws Exception{
  if(!status().optBoolean("enabled"))throw new IllegalStateException("Turn on Wi-Fi first");
  boolean exists=false;for(WifiConfiguration c:configurations())exists|=c.networkId==id;if(!exists)throw new IllegalArgumentException("Saved network is no longer available");
  if(status().optInt("id",-1)==id&&status().optBoolean("connected"))return new JSONObject().put("accepted",true).put("already",true);
  Object s=service();boolean accepted=(Boolean)s.getClass().getMethod("enableNetwork",int.class,boolean.class,String.class).invoke(s,id,true,"com.android.shell");
  if(!accepted)throw new IllegalStateException("Android did not accept the connection");return new JSONObject().put("accepted",true);
 }
 static JSONObject join(JSONObject j)throws Exception{
  String ssid=j.getString("s"),security=j.getString("t"),password=j.optString("p","");byte[] name=ssid.getBytes(StandardCharsets.UTF_8);
  if(name.length<1||name.length>32||ssid.indexOf('\0')>=0)throw new IllegalArgumentException("Network name must be 1–32 bytes");
  if(!Arrays.asList("open","owe","wpa2","wpa3").contains(security))throw new IllegalArgumentException("Configure enterprise Wi-Fi on the device");
  if(security.equals("wpa2")&&!(password.matches("[a-fA-F0-9]{64}")||(password.getBytes(StandardCharsets.UTF_8).length>=8&&password.getBytes(StandardCharsets.UTF_8).length<=63)))throw new IllegalArgumentException("WPA2 password must be 8–63 bytes");
  if(security.equals("wpa3")&&(password.getBytes(StandardCharsets.UTF_8).length<1||password.getBytes(StandardCharsets.UTF_8).length>63))throw new IllegalArgumentException("WPA3 password must be 1–63 bytes");
  // Existing saved configurations (especially enterprise validation and BSSID preferences) stay intact.
  for(WifiConfiguration old:configurations())if(name(old.SSID).equals(ssid)&&security(old).equals(security))return connectSaved(old.networkId);
  WifiConfiguration config=new WifiConfiguration();config.SSID=JSONObject.quote(ssid);
  if(security.equals("wpa2")||security.equals("wpa3")){config.preSharedKey=password.matches("[a-fA-F0-9]{64}")&&security.equals("wpa2")?password:JSONObject.quote(password);config.allowedKeyManagement.set(security.equals("wpa3")?WifiConfiguration.KeyMgmt.SAE:WifiConfiguration.KeyMgmt.WPA_PSK);}else config.allowedKeyManagement.set(security.equals("owe")?WifiConfiguration.KeyMgmt.OWE:WifiConfiguration.KeyMgmt.NONE);
  // Firmware derives protected-management-frame settings from the security type.
  int type=security.equals("wpa2")?2:security.equals("wpa3")?4:security.equals("owe")?6:0;
  WifiConfiguration.class.getMethod("setSecurityParams",int.class).invoke(config,type);
  Object s=service();int id=(Integer)s.getClass().getMethod("addOrUpdateNetwork",WifiConfiguration.class,String.class,Bundle.class).invoke(s,config,"com.android.shell",new Bundle());if(id<0)throw new IllegalStateException("Android could not save this network");return connectSaved(id);
 }
 static JSONObject command(JSONObject request)throws Exception{
  String command=request.getString("set");JSONObject result;
  switch(command){case "wifi_portal":IBinder binder=(IBinder)Class.forName("android.os.ServiceManager").getMethod("getService",String.class).invoke(null,"connectivity");Object cm=Class.forName("android.net.IConnectivityManager$Stub").getMethod("asInterface",IBinder.class).invoke(null,binder);cm.getClass().getMethod("startCaptivePortalApp",android.net.Network.class).invoke(cm,android.net.Network.fromNetworkHandle(request.getLong("value")));result=new JSONObject().put("opened",true);break;case "wifi_enable":if(WifiAccess.integer(request.get("value"))!=1)throw new IllegalArgumentException("Invalid Wi-Fi action");ActivityProbe.command("/system/bin/cmd","wifi","set-wifi-enabled","enabled");result=new JSONObject().put("accepted",true);break;case "wifi_status":result=status();break;case "wifi_saved":result=new JSONObject().put("items",saved());break;case "wifi_scan":result=new JSONObject().put("items",scan(request.optBoolean("refresh")));break;case "wifi_connect":result=connectSaved(WifiAccess.integer(request.get("value")));break;case "wifi_join":result=join(request.getJSONObject("value"));break;default:throw new IllegalArgumentException("Unsupported Wi-Fi action");}
  return result.put("ok",true);
 }
}
