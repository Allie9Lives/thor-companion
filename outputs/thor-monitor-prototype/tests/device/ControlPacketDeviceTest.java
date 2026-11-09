package com.alan.thormonitor.tests;
import android.app.*;import android.os.*;import android.content.*;import org.json.*;import java.lang.reflect.*;import java.nio.charset.StandardCharsets;
public class ControlPacketDeviceTest extends Instrumentation {
 public void onCreate(Bundle b){super.onCreate(b);start();}
 public void onStart(){Bundle result=new Bundle();try{
  Context c=getTargetContext();ClassLoader loader=c.getClassLoader();Class<?> controls=loader.loadClass("com.alan.thormonitor.ThorControls"),packet=loader.loadClass("com.alan.thormonitor.ControlPacket");
  Constructor<?> constructor=controls.getDeclaredConstructor(Context.class);constructor.setAccessible(true);Object target=constructor.newInstance(c);Method snapshot=controls.getDeclaredMethod("snapshot");snapshot.setAccessible(true);JSONObject full=(JSONObject)snapshot.invoke(target);
  Method encode=packet.getDeclaredMethod("bluetooth",JSONObject.class);encode.setAccessible(true);
  String original=full.toString();byte[] bytes=(byte[])encode.invoke(null,full);JSONObject decoded=new JSONObject(new String(bytes,StandardCharsets.UTF_8));
  if(bytes.length>512||!original.equals(full.toString()))throw new AssertionError("Size limit or source mutation");
  for(String key:new String[]{"settings","power_control","finder","find","history","sleep_policy","sleep_end","sleep_suspended","sleep_exact","sleep_restore_at","wake_control","screens_awake","keyboard","keyboard_selected","activity","hz","fan","ack","error"})if(!decoded.has(key))throw new AssertionError("Missing client field "+key);
  result.putInt("full_status_bytes",full.toString().getBytes(StandardCharsets.UTF_8).length);result.putInt("bluetooth_status_bytes",bytes.length);
  StringBuilder error=new StringBuilder();for(int i=0;i<140;i++)error.append("🔥");full.put("ack","abcdefghijklmnopqrstuvwxyz123456").put("error",error.toString());bytes=(byte[])encode.invoke(null,full);decoded=new JSONObject(new String(bytes,StandardCharsets.UTF_8));
  if(bytes.length>512||!decoded.getString("ack").equals("abcdefghijklmnopqrstuvwxyz123456")||decoded.getString("error").isEmpty()||!decoded.has("sleep_end"))throw new AssertionError("Long Unicode error packet");
  JSONObject detail=new JSONObject().put("v",1).put("ack","history").put("error","").put("history",new JSONArray().put(new JSONArray().put(1).put(80)));bytes=(byte[])encode.invoke(null,detail);if(!new JSONObject(new String(bytes,StandardCharsets.UTF_8)).toString().equals(detail.toString()))throw new AssertionError("History packet changed");
  JSONObject link=new JSONObject().put("ack","network").put("pin","abc").put("token","def").put("hosts",new JSONArray().put("127.0.0.1"));bytes=(byte[])encode.invoke(null,link);if(!new JSONObject(new String(bytes,StandardCharsets.UTF_8)).toString().equals(link.toString()))throw new AssertionError("Network detail changed");
  result.putString("status","passed: live fields, bounded Unicode errors and unchanged detail replies");finish(0,result);
 }catch(Throwable e){result.putString("error",e.toString());finish(1,result);}}
}
