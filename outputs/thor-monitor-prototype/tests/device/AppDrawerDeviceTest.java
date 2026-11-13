package com.alan.thormonitor.tests;
import android.app.*;import android.content.*;import android.os.*;import java.lang.reflect.*;import org.json.*;
public class AppDrawerDeviceTest extends Instrumentation {
 public void onCreate(Bundle b){super.onCreate(b);start();}
 private Context c;private Method action;
 private void screen(int display)throws Exception{
  Class<?> monitor=c.getClassLoader().loadClass("com.alan.thormonitor.ActivityMonitor");Constructor<?> ctor=monitor.getDeclaredConstructor(Context.class);ctor.setAccessible(true);Object instance=ctor.newInstance(c);Method sample=monitor.getDeclaredMethod("sample",JSONObject.class),reply=monitor.getDeclaredMethod("reply",String.class);sample.setAccessible(true);reply.setAccessible(true);sample.invoke(instance,new JSONObject());JSONObject snapshot=(JSONObject)reply.invoke(instance,"verify");JSONArray apps=snapshot.optJSONArray("apps");boolean found=false;
  if(apps!=null)for(int i=0;i<apps.length();i++){JSONObject app=apps.getJSONObject(i);if(app.optInt("d",-1)==display&&app.optString("p").equals("com.android.settings"))found=true;}
  if(!found)throw new AssertionError("Settings was not focused on display "+display);
 }
 public void onStart(){Bundle result=new Bundle();c=getTargetContext();String stage="catalog";try{
  Class<?> catalog=c.getClassLoader().loadClass("com.alan.thormonitor.AppCatalog");Method page=catalog.getDeclaredMethod("page",Context.class,int.class,String.class);page.setAccessible(true);action=catalog.getDeclaredMethod("action",Context.class,String.class,String.class,String.class);action.setAccessible(true);
  int cursor=0,count=0,pages=0;do{JSONObject j=(JSONObject)page.invoke(null,c,cursor,"abcdefghijklmnopqrstuvwxyz123456");if(j.toString().getBytes("UTF-8").length>512)throw new AssertionError("App page exceeds ATT limit");JSONArray apps=j.getJSONArray("apps");count+=apps.length();cursor=j.getInt("next");if(++pages>500)throw new AssertionError("Pagination loop");}while(cursor>=0);
  if(count==0)throw new AssertionError("Launcher catalog empty");
  stage="open top";action.invoke(null,c,"app_open","com.android.settings","top");Thread.sleep(900);screen(0);
  stage="move bottom";action.invoke(null,c,"app_open","com.android.settings","bottom");Thread.sleep(900);screen(4);
  action.invoke(null,c,"app_open","com.android.settings","top");Thread.sleep(900);screen(0);
  stage="open-app catalog";Method openPage=catalog.getDeclaredMethod("openPage",Context.class,int.class,String.class);openPage.setAccessible(true);JSONObject opened=(JSONObject)openPage.invoke(null,c,0,"open-check");boolean settings=false;for(int i=0;i<opened.getJSONArray("apps").length();i++){JSONObject app=opened.getJSONArray("apps").getJSONObject(i);if(app.optString("p").equals("com.android.settings")){settings=true;if(!app.optBoolean("can_stop"))throw new AssertionError("Open Settings missing Stop");Method icon=catalog.getDeclaredMethod("icon",Context.class,String.class,String.class);icon.setAccessible(true);byte[] png=(byte[])icon.invoke(null,c,app.getString("p"),app.getString("icon"));if(png.length<24||png.length>32768||png[1]!='P')throw new AssertionError("Invalid app icon");}}if(!settings)throw new AssertionError("Open Settings missing from drawer");
  stage="close";action.invoke(null,c,"app_close","com.android.settings","top");
  stage="closed-app guard";try{action.invoke(null,c,"app_close","com.android.settings","top");throw new AssertionError("Stop allowed on a closed app");}catch(InvocationTargetException expected){if(!(expected.getCause() instanceof IllegalStateException))throw expected;}
  stage="host protection";try{action.invoke(null,c,"app_close","com.alan.thormonitor","top");throw new AssertionError("Remote host stop accepted");}catch(InvocationTargetException expected){if(!(expected.getCause() instanceof IllegalArgumentException))throw expected;}
  try{action.invoke(null,c,"app_open","com.android.settings;reboot","top");throw new AssertionError("Malformed package accepted");}catch(InvocationTargetException expected){if(!(expected.getCause() instanceof IllegalArgumentException))throw expected;}
  result.putInt("launcher_apps",count);result.putInt("pages",pages);result.putString("status","passed: bounded app catalog, top/bottom launch and task move, close, host protection and argument validation");finish(0,result);
 }catch(Throwable e){result.putString("error",stage+": "+e.toString()+(e.getCause()==null?"":" cause="+e.getCause()));finish(1,result);}}
}
