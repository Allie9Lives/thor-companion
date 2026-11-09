package com.alan.thormonitor;
import android.content.*;import android.net.*;import android.os.*;import org.json.*;import java.io.*;
final class ActivityMonitor {
 private final Context app;private final ClosedLidPolicy policy=new ClosedLidPolicy();private JSONObject cached=new JSONObject();private long last,warning;private String reason="";
 ActivityMonitor(Context c){app=c;}
 synchronized void sample(JSONObject telemetry){
  long now=SystemClock.elapsedRealtime();if(last>0&&now-last<25000)return;last=now;
  try(LocalSocket socket=new LocalSocket()){
   socket.connect(new LocalSocketAddress(ThorControls.socketName(app),LocalSocketAddress.Namespace.ABSTRACT));socket.setSoTimeout(8000);if(socket.getPeerCredentials().getUid()!=2000)throw new SecurityException();
   byte[] request="{\"set\":\"activity\",\"value\":0}".getBytes("UTF-8");DataOutputStream out=new DataOutputStream(socket.getOutputStream());out.writeShort(request.length);out.write(request);out.flush();DataInputStream in=new DataInputStream(socket.getInputStream());int length=in.readUnsignedShort();if(length>4096)throw new IOException();byte[] bytes=new byte[length];in.readFully(bytes);JSONObject j=new JSONObject(new String(bytes,"UTF-8"));if(!j.optBoolean("ok"))throw new IOException();
   JSONArray apps=j.getJSONArray("apps");double peak=-1;for(int i=0;i<apps.length();i++){JSONObject entry=apps.getJSONObject(i);String pkg=entry.getString("p"),label=pkg;try{label=app.getPackageManager().getApplicationLabel(app.getPackageManager().getApplicationInfo(pkg,0)).toString();}catch(Exception ignored){}entry.put("name",label.substring(0,Math.min(40,label.length())));peak=Math.max(peak,entry.optDouble("cpu",-1));}
   Boolean closed=j.isNull("lid")?null:j.getBoolean("lid");double gpu=telemetry.optDouble("gpu_percent",-1);boolean trigger=policy.observe(now,closed,peak,gpu,telemetry.optDouble("battery_percent",Double.NaN),telemetry.optInt("plugged_code",0)!=0);
   if(trigger){warning=System.currentTimeMillis();reason=peak>=12.5?"App CPU activity remains high":gpu>=30?"Device GPU activity remains high":"Battery dropped at least 3 points while closed";}
   cached=new JSONObject().put("at",System.currentTimeMillis()).put("lid",closed==null?JSONObject.NULL:closed).put("closed_s",policy.seconds(now)).put("apps",apps).put("gpu",gpu<0?JSONObject.NULL:gpu).put("warning",warning).put("reason",reason);
  }catch(Exception e){cached=new JSONObject();try{cached.put("error","Activity unavailable; check Automatic recovery");}catch(Exception ignored){}policy.observe(now,null,-1,-1,Double.NaN,false);}
 }
 synchronized JSONObject reply(String id)throws Exception{JSONObject j=new JSONObject(cached.toString()).put("ack",id);if(!j.has("at")&&!j.has("error"))j.put("error","Waiting for the first activity sample");if(!j.has("error"))j.put("error","");if(j.toString().getBytes("UTF-8").length>500){JSONArray apps=j.optJSONArray("apps");if(apps!=null)for(int i=0;i<apps.length();i++)apps.getJSONObject(i).remove("name");}return j;}
}
