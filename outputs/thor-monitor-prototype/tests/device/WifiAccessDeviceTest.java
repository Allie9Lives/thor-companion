package com.alan.thormonitor.tests;
import android.app.*;import android.os.*;import android.content.*;import org.json.*;import java.lang.reflect.*;import java.nio.charset.StandardCharsets;import java.util.*;
public class WifiAccessDeviceTest extends Instrumentation {
 public void onCreate(Bundle b){super.onCreate(b);start();}
 public void onStart(){Bundle result=new Bundle();try{
  Context c=getTargetContext();ClassLoader loader=c.getClassLoader();Class<?> controls=loader.loadClass("com.alan.thormonitor.ThorControls"),wifi=loader.loadClass("com.alan.thormonitor.WifiAccess"),packet=loader.loadClass("com.alan.thormonitor.ControlPacket");
  Constructor<?> ctor=controls.getDeclaredConstructor(Context.class);ctor.setAccessible(true);Object target=ctor.newInstance(c);Method exchange=controls.getDeclaredMethod("exchange",byte[].class);exchange.setAccessible(true);Method encode=packet.getDeclaredMethod("bluetooth",JSONObject.class);encode.setAccessible(true);
  JSONObject status=send(exchange,target,"wifi_status",0);if(!status.optBoolean("known")||!status.optBoolean("connected"))throw new AssertionError("Current Wi-Fi unavailable: "+status.optString("error"));
  int cursor=0,count=0;JSONObject current=null;
  do{JSONObject page=send(exchange,target,"wifi_saved",cursor);byte[] bytes=(byte[])encode.invoke(null,page);if(bytes.length>512||!page.optString("error").isEmpty())throw new AssertionError("Invalid saved page");JSONArray items=page.getJSONArray("items");for(int i=0;i<items.length();i++){JSONObject n=items.getJSONObject(i);if(n.length()!=3)throw new AssertionError("Unsanitized network");if(n.getInt("id")==status.getInt("id"))current=n;count++;}cursor=page.getInt("next");if(count>200)throw new AssertionError("Pagination loop");}while(cursor>=0);
  if(current==null)throw new AssertionError("Current saved network missing");
  String session="wifiTest",secret="test-only-not-saved";byte[] config=new JSONObject().put("s",current.getString("n")).put("t",current.getString("s")).put("p",secret).toString().getBytes(StandardCharsets.UTF_8);
  for(int pos=0,n=0;pos<config.length;pos+=36,n++){byte[] part=Arrays.copyOfRange(config,pos,Math.min(pos+36,config.length));JSONObject reply=send(exchange,target,"wifi_stage",new JSONObject().put("s",session).put("n",n).put("b",android.util.Base64.encodeToString(part,2)));if(!reply.optString("error").isEmpty())throw new AssertionError("Staging rejected");}
  JSONObject commit=send(exchange,target,"wifi_commit",session);if(!commit.optBoolean("already"))throw new AssertionError("Existing network no-op failed: "+commit.optString("error"));
  Field buffer=wifi.getDeclaredField("staged");buffer.setAccessible(true);for(byte b:(byte[])buffer.get(null))if(b!=0)throw new AssertionError("Password stage not cleared");
  if(send(exchange,target,"wifi_connect",2.5).optString("error").isEmpty())throw new AssertionError("Fractional ID accepted");
  if(send(exchange,target,"wifi_commit",session).optString("error").isEmpty())throw new AssertionError("Expired stage accepted");
  Class<?> tele=loader.loadClass("com.alan.thormonitor.Telemetry"),service=loader.loadClass("com.alan.thormonitor.MonitorService");Constructor<?> tc=tele.getDeclaredConstructor();tc.setAccessible(true);Method sample=tele.getDeclaredMethod("sample",Context.class,long.class);sample.setAccessible(true);JSONObject stats=(JSONObject)sample.invoke(tc.newInstance(),c,1L);Method value=service.getDeclaredMethod("value",UUID.class,JSONObject.class);value.setAccessible(true);Field statsId=service.getDeclaredField("STATS");statsId.setAccessible(true);byte[] statsBytes=(byte[])value.invoke(service.newInstance(),statsId.get(null),stats);
  result.putInt("stats_bytes",statsBytes.length);result.putInt("saved_count",count);result.putString("status","passed: paged networks, current-network no-op join, bounded encrypted staging, cleared credentials, invalid IDs rejected");finish(0,result);
 }catch(Throwable e){result.putString("error",e.toString());finish(1,result);}}
 private static int seq;
 private JSONObject send(Method exchange,Object target,String set,Object value)throws Exception{
  String id="wifi-test-"+(seq++);byte[] bytes=new JSONObject().put("id",id).put("set",set).put("value",value).toString().getBytes(StandardCharsets.UTF_8);if(bytes.length>180)throw new AssertionError("Request too large");JSONObject reply=(JSONObject)exchange.invoke(target,(Object)bytes);if(!id.equals(reply.optString("ack")))throw new AssertionError("Missing ACK");return reply;
 }
}
