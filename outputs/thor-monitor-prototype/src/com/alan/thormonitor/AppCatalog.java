package com.alan.thormonitor;
import android.content.*;import android.content.pm.*;import java.util.*;import java.io.*;import org.json.*;
final class AppCatalog {
 private static List<JSONObject> cached,cachedOpen;private static long loaded,openLoaded;
 static boolean validPackage(String name){return AppActions.validPackage(name);}

 static List<ResolveInfo> launchers(Context c){return c.getPackageManager().queryIntentActivities(new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER),0);}
 static String revision(Context c,ResolveInfo r)throws Exception{
  PackageInfo p=c.getPackageManager().getPackageInfo(r.activityInfo.packageName,0);
  String input=r.activityInfo.packageName+"|"+p.getLongVersionCode()+"|"+p.lastUpdateTime+"|"+r.activityInfo.name+"|"+r.activityInfo.getIconResource();
  byte[] hash=java.security.MessageDigest.getInstance("SHA-256").digest(input.getBytes("UTF-8"));return FileAccess.hex(hash).substring(0,16);
 }
 static String iconRevision(Context c,String pkg)throws Exception{for(ResolveInfo r:launchers(c))if(r.activityInfo.packageName.equals(pkg))return revision(c,r);return "";}
 static byte[] icon(Context c,String pkg,String expected)throws Exception{
  if(!validPackage(pkg)||!expected.matches("[a-f0-9]{16}"))throw new IllegalArgumentException("Invalid icon request");
  for(ResolveInfo r:launchers(c))if(r.activityInfo.packageName.equals(pkg)&&revision(c,r).equals(expected)&&r.activityInfo.getIconResource()!=0){
   android.graphics.drawable.Drawable drawable=r.loadIcon(c.getPackageManager());
   for(int size:new int[]{128,64}){android.graphics.Bitmap bitmap=android.graphics.Bitmap.createBitmap(size,size,android.graphics.Bitmap.Config.ARGB_8888);try{drawable.setBounds(0,0,size,size);drawable.draw(new android.graphics.Canvas(bitmap));java.io.ByteArrayOutputStream bytes=new java.io.ByteArrayOutputStream();bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,bytes);if(bytes.size()<=32768)return bytes.toByteArray();}finally{bitmap.recycle();}}
  }throw new java.io.FileNotFoundException("App icon unavailable or app changed");
 }
 static Map<String,JSONArray> tasks(Context c)throws Exception{
  try(android.net.LocalSocket socket=new android.net.LocalSocket()){
   socket.connect(new android.net.LocalSocketAddress(ThorControls.socketName(c),android.net.LocalSocketAddress.Namespace.ABSTRACT));socket.setSoTimeout(8000);if(socket.getPeerCredentials().getUid()!=2000)throw new SecurityException();byte[] request="{\"set\":\"app_tasks\"}".getBytes("UTF-8");DataOutputStream out=new DataOutputStream(socket.getOutputStream());out.writeShort(request.length);out.write(request);out.flush();DataInputStream in=new DataInputStream(socket.getInputStream());int size=in.readUnsignedShort();if(size>32768)throw new IOException();byte[] bytes=new byte[size];in.readFully(bytes);JSONObject data=new JSONObject(new String(bytes,"UTF-8"));if(!data.optBoolean("ok"))throw new IllegalStateException("Update Controls recovery for open-app status");
   Map<String,JSONArray> result=new HashMap<>();JSONArray rows=data.getJSONArray("tasks");for(int i=0;i<rows.length();i++){JSONObject row=rows.getJSONObject(i);String pkg=row.getString("p");JSONArray screens=result.get(pkg);if(screens==null){screens=new JSONArray();result.put(pkg,screens);}int display=row.getInt("d");boolean seen=false;for(int n=0;n<screens.length();n++)seen|=screens.getInt(n)==display;if(!seen)screens.put(display);}return result;
  }
 }
 static boolean protectedApp(Context c,String pkg){ResolveInfo home=c.getPackageManager().resolveActivity(new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME),0);return pkg.equals(c.getPackageName())||pkg.equals("com.android.systemui")||pkg.equals("com.android.launcher3")||(home!=null&&pkg.equals(home.activityInfo.packageName));}
 static synchronized JSONObject openPage(Context c,int cursor,String id)throws Exception{
  if(cursor<0)throw new IllegalArgumentException();if(cursor==0){Map<String,JSONArray> opened=tasks(c);cachedOpen=new ArrayList<>();for(ResolveInfo app:launchers(c)){String pkg=app.activityInfo.packageName;if(!opened.containsKey(pkg))continue;boolean seen=false;for(JSONObject prior:cachedOpen)seen|=prior.optString("p").equals(pkg);if(seen)continue;String name=app.loadLabel(c.getPackageManager()).toString();if(name.codePointCount(0,name.length())>32)name=name.substring(0,name.offsetByCodePoints(0,32));cachedOpen.add(new JSONObject().put("p",pkg).put("name",name).put("icon",revision(c,app)).put("displays",opened.get(pkg)).put("can_stop",!protectedApp(c,pkg)));}cachedOpen.sort(Comparator.comparing(j->j.optString("name").toLowerCase(Locale.ROOT)));openLoaded=android.os.SystemClock.elapsedRealtime();}
  if(cachedOpen==null||cursor>cachedOpen.size()||android.os.SystemClock.elapsedRealtime()-openLoaded>120000)throw new IllegalStateException("Refresh open apps");JSONArray rows=new JSONArray();JSONObject result=new JSONObject().put("ack",id).put("error","").put("apps",rows).put("next",-1);int at=cursor;while(at<cachedOpen.size()){rows.put(cachedOpen.get(at));result.put("next",at+1);if(result.toString().getBytes("UTF-8").length>490){rows.remove(rows.length()-1);break;}at++;}if(at<cachedOpen.size()&&rows.length()==0)throw new IllegalStateException("App details exceed Bluetooth limit");return result.put("next",at<cachedOpen.size()?at:-1);
 }
 static synchronized JSONObject page(Context c,int cursor,String id)throws Exception{
  if(cursor<0)throw new IllegalArgumentException("Invalid app cursor");
  if(cursor==0){
   Map<String,JSONObject> unique=new HashMap<>();
   for(ResolveInfo r:launchers(c)){String pkg=r.activityInfo.packageName;if(!validPackage(pkg))continue;String name=r.loadLabel(c.getPackageManager()).toString();if(name.codePointCount(0,name.length())>32)name=name.substring(0,name.offsetByCodePoints(0,32));unique.put(pkg,new JSONObject().put("p",pkg).put("name",name).put("icon",revision(c,r)));}
   cached=new ArrayList<>(unique.values());cached.sort(Comparator.comparing(j->j.optString("name").toLowerCase(Locale.ROOT)));loaded=android.os.SystemClock.elapsedRealtime();
  }
  if(cached==null||android.os.SystemClock.elapsedRealtime()-loaded>120000||cursor>cached.size())throw new IllegalStateException("App list changed. Refresh the drawer.");
  JSONArray entries=new JSONArray();JSONObject reply=new JSONObject().put("ack",id).put("error","").put("apps",entries).put("next",-1).put("total",cached.size());int at=cursor;
  while(at<cached.size()){
   entries.put(cached.get(at));reply.put("next",at+1<cached.size()?at+1:-1);
   if(reply.toString().getBytes("UTF-8").length>490){entries.remove(entries.length()-1);break;}at++;
  }
  if(at<cached.size()&&entries.length()==0)throw new IllegalStateException("App details exceed Bluetooth limit");
  reply.put("next",at<cached.size()?at:-1);return reply;
 }
 static void action(Context c,String kind,String pkg,String target)throws Exception{
  if(!validPackage(pkg)||!Arrays.asList("app_open","app_close").contains(kind))throw new IllegalArgumentException("Invalid app action");
  boolean found=false;for(ResolveInfo r:launchers(c))if(r.activityInfo.packageName.equals(pkg))found=true;
  if(!found)throw new IllegalStateException("This app is not available in the launcher");
  if(kind.equals("app_close")){
   if(protectedApp(c,pkg))throw new IllegalArgumentException("The host and home launcher cannot be closed remotely");
   if(!tasks(c).containsKey(pkg))throw new IllegalStateException("This app is no longer open");
  }
  int display=target.equals("top")?0:target.equals("bottom")?4:-1;if(display<0)throw new IllegalArgumentException("Choose Top or Bottom screen");
  JSONObject request=new JSONObject().put("set",kind).put("value",pkg).put("target",display);
  try(android.net.LocalSocket socket=new android.net.LocalSocket()){
   socket.connect(new android.net.LocalSocketAddress(ThorControls.socketName(c),android.net.LocalSocketAddress.Namespace.ABSTRACT));socket.setSoTimeout(12000);if(socket.getPeerCredentials().getUid()!=2000)throw new SecurityException();
   byte[] bytes=request.toString().getBytes("UTF-8");if(bytes.length>180)throw new IllegalArgumentException("App identifier too long");DataOutputStream out=new DataOutputStream(socket.getOutputStream());out.writeShort(bytes.length);out.write(bytes);out.flush();DataInputStream in=new DataInputStream(socket.getInputStream());int n=in.readUnsignedShort();if(n>512)throw new IOException();byte[] result=new byte[n];in.readFully(result);JSONObject response=new JSONObject(new String(result,"UTF-8"));if(!response.optBoolean("ok"))throw new IllegalStateException(response.optString("error","App control failed. Check Controls recovery."));
  }
 }
}
