package com.alan.thormonitor;
import android.content.*;import android.net.*;import android.os.*;import org.json.*;import java.io.*;import java.nio.charset.StandardCharsets;import java.util.*;import java.util.concurrent.*;
/** App-side Wi-Fi broker. Password staging is bounded, transient and never persisted. */
final class WifiAccess {
 private static final ExecutorService worker=Executors.newSingleThreadExecutor();
 private static JSONObject state=new JSONObject();private static boolean busy;private static long checked;
 private static final byte[] staged=new byte[1024];private static String stage="";private static int used,index;private static long expires;
 private static JSONArray saved=new JSONArray(),nearby=new JSONArray();private static long savedAt,nearbyAt;
 static JSONObject helper(Context c,JSONObject request)throws Exception{
  try(LocalSocket s=new LocalSocket()){s.connect(new LocalSocketAddress(ThorControls.socketName(c),LocalSocketAddress.Namespace.ABSTRACT));s.setSoTimeout(6000);if(s.getPeerCredentials().getUid()!=2000)throw new SecurityException();
   byte[] bytes=request.toString().getBytes(StandardCharsets.UTF_8);if(bytes.length>4096)throw new IllegalArgumentException("Wi-Fi request too large");DataOutputStream out=new DataOutputStream(s.getOutputStream());out.writeShort(bytes.length);out.write(bytes);out.flush();DataInputStream in=new DataInputStream(s.getInputStream());int n=in.readUnsignedShort();if(n>32768)throw new IOException();byte[] reply=new byte[n];in.readFully(reply);JSONObject j=new JSONObject(new String(reply,StandardCharsets.UTF_8));if(!j.optBoolean("ok"))throw new IllegalStateException(j.optString("error","Check Controls recovery on the Thor"));return j;
  }catch(IOException e){throw new IllegalStateException("Update Thor Monitor and check Controls recovery");}
 }
 static synchronized JSONObject cached(Context c){if(!state.has("known")){try{state=new JSONObject(c.getSharedPreferences("monitor",0).getString("wifi_state","{}"));}catch(Exception ignored){}}try{return new JSONObject(state.toString());}catch(Exception e){return new JSONObject();}}
 static Network wifiNetwork(Context c){ConnectivityManager cm=c.getSystemService(ConnectivityManager.class);for(Network n:cm.getAllNetworks()){NetworkCapabilities cap=cm.getNetworkCapabilities(n);if(cap!=null&&cap.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)&&!cap.hasTransport(NetworkCapabilities.TRANSPORT_VPN))return n;}return null;}
 static void refresh(Context c){synchronized(WifiAccess.class){if(busy||SystemClock.elapsedRealtime()-checked<5000)return;busy=true;checked=SystemClock.elapsedRealtime();}worker.execute(()->{try{update(c);}catch(Exception ignored){}finally{synchronized(WifiAccess.class){busy=false;}}});}
 static synchronized JSONObject update(Context c)throws Exception{
  JSONObject next=helper(c,new JSONObject().put("set","wifi_status"));Network wifi=wifiNetwork(c);NetworkCapabilities cap=wifi==null?null:c.getSystemService(ConnectivityManager.class).getNetworkCapabilities(wifi);next.put("captive",cap!=null&&cap.hasCapability(NetworkCapabilities.NET_CAPABILITY_CAPTIVE_PORTAL)).put("validated",cap!=null&&cap.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED));
  JSONObject old=cached(c);boolean change=old.optBoolean("known")&&(!next.optString("name").equals(old.optString("name"))||next.optBoolean("connected")!=old.optBoolean("connected")||next.optBoolean("captive")!=old.optBoolean("captive"));long now=System.currentTimeMillis();long event=old.optLong("event",1);if(event<1||event>65535)event=1;if(change)event=event%65535+1;next.put("event",event).put("changed_at",change?now:old.optLong("changed_at",now));state=next;c.getSharedPreferences("monitor",0).edit().putString("wifi_state",state.toString()).apply();return new JSONObject(state.toString());
 }
 static void clear(){Arrays.fill(staged,(byte)0);used=index=0;stage="";expires=0;}
 static int integer(Object value)throws Exception{if(!(value instanceof Number)||((Number)value).doubleValue()!=((Number)value).intValue())throw new IllegalArgumentException("Integer value required");return ((Number)value).intValue();}
 static synchronized JSONObject command(Context c,String key,Object value,String ack)throws Exception{
  JSONObject result=new JSONObject();
  if(key.equals("wifi_status")){integer(value);result=update(c);}
  else if(key.equals("wifi_saved")||key.equals("wifi_scan")){
   int cursor=integer(value);if(cursor<0||cursor>200)throw new IllegalArgumentException("Invalid network page");long now=SystemClock.elapsedRealtime();boolean scan=key.equals("wifi_scan");if(cursor==0){JSONArray list=helper(c,new JSONObject().put("set",key).put("refresh",scan)).getJSONArray("items");if(scan){nearby=list;nearbyAt=now;}else{saved=list;savedAt=now;}}
   JSONArray source=scan?nearby:saved;if(now-(scan?nearbyAt:savedAt)>60000)throw new IllegalStateException("Refresh the network list");JSONArray page=new JSONArray();int end=Math.min(source.length(),cursor+1);for(int i=cursor;i<end;i++)page.put(source.get(i));result.put("items",page).put("next",end<source.length()?end:-1);
  }else if(key.equals("wifi_enable")){if(integer(value)!=1)throw new IllegalArgumentException("Invalid Wi-Fi action");result=helper(c,new JSONObject().put("set",key).put("value",1));checked=0;refresh(c);}
  else if(key.equals("wifi_connect")){result=helper(c,new JSONObject().put("set",key).put("value",integer(value)));checked=0;refresh(c);}
  else if(key.equals("wifi_stage")){
   if(!(value instanceof JSONObject))throw new IllegalArgumentException("Invalid network details");JSONObject v=(JSONObject)value;String token=v.getString("s");int n=integer(v.get("n"));if(!token.matches("[a-zA-Z0-9]{1,24}")||n<0)throw new IllegalArgumentException("Invalid network details");
   if(n==0){clear();stage=token;expires=SystemClock.elapsedRealtime()+60000;final String pending=stage;new Handler(Looper.getMainLooper()).postDelayed(()->{synchronized(WifiAccess.class){if(stage.equals(pending)&&expires<=SystemClock.elapsedRealtime())clear();}},60050);}if(!stage.equals(token)||expires<SystemClock.elapsedRealtime()||n!=index){clear();throw new IllegalArgumentException("Network details expired; try again");}
   byte[] part=android.util.Base64.decode(v.getString("b"),android.util.Base64.NO_WRAP);if(part.length<1||part.length>48||used+part.length>staged.length){clear();throw new IllegalArgumentException("Network details too large");}System.arraycopy(part,0,staged,used,part.length);used+=part.length;index++;Arrays.fill(part,(byte)0);
  }else if(key.equals("wifi_commit")){
   if(!(value instanceof String)||!stage.equals(value)||used==0||expires<SystemClock.elapsedRealtime()){clear();throw new IllegalArgumentException("Network details expired; try again");}
   try{JSONObject config=new JSONObject(new String(staged,0,used,StandardCharsets.UTF_8));result=helper(c,new JSONObject().put("set","wifi_join").put("value",config));}finally{clear();}checked=0;refresh(c);
  }else if(key.equals("wifi_portal")){
   if(integer(value)!=0)throw new IllegalArgumentException("Invalid sign-in request");Network n=wifiNetwork(c);if(n==null)throw new IllegalStateException("Connect the Thor to Wi-Fi first");helper(c,new JSONObject().put("set","wifi_portal").put("value",n.getNetworkHandle()));result.put("opened",true);
  }else throw new IllegalArgumentException("Unsupported Wi-Fi action");
  return result.put("ack",ack).put("error","");
 }
}
