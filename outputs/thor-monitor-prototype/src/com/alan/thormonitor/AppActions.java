package com.alan.thormonitor;
import java.util.regex.*;
/** Shell helper actions use fixed argument arrays; package names never become shell code. */
final class AppActions {
 static boolean validPackage(String name){return name!=null&&name.length()<=96&&name.matches("[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)+");}
 static int rootFor(String stacks,String pkg){
  int root=-1;for(String line:stacks.split("\n")){
   Matcher header=Pattern.compile("^RootTask id=(\\d+) .* userId=0$").matcher(line);if(header.find())root=Integer.parseInt(header.group(1));
   if(root>=0&&line.trim().matches("taskId=\\d+: "+Pattern.quote(pkg)+"/.*userId=0.*"))return root;
  }return -1;
 }
 static org.json.JSONArray tasks()throws Exception{
  org.json.JSONArray result=new org.json.JSONArray();int display=-1;
  for(String line:ActivityProbe.command("/system/bin/am","stack","list").split("\n")){
   Matcher header=Pattern.compile("^RootTask id=\\d+ .*displayId=(\\d+) userId=0$").matcher(line);if(header.find())display=Integer.parseInt(header.group(1));
   Matcher task=Pattern.compile("^\\s*taskId=(\\d+): ([A-Za-z0-9_.]+)/.*userId=0.*$").matcher(line);
   if((display==0||display==4)&&task.find()&&validPackage(task.group(2))){result.put(new org.json.JSONObject().put("p",task.group(2)).put("d",display));if(result.length()>=128)break;}
  }return result;
 }
 static int[] taskFor(String stacks,String pkg,int preferred){
  int root=-1,display=-1;int[] fallback=null;
  for(String line:stacks.split("\n")){
   Matcher header=Pattern.compile("^RootTask id=(\\d+) .*displayId=(\\d+) userId=0$").matcher(line);if(header.find()){root=Integer.parseInt(header.group(1));display=Integer.parseInt(header.group(2));}
   Matcher task=Pattern.compile("^\\s*taskId=(\\d+): "+Pattern.quote(pkg)+"/.*userId=0.*$").matcher(line);
   if(root>=0&&task.find()){int[] found={root,Integer.parseInt(task.group(1)),display};if(display==preferred)return found;if(fallback==null)fallback=found;}
  }return fallback;
 }
 static boolean focusTask(int task){try{Object service=Class.forName("android.app.ActivityTaskManager").getDeclaredMethod("getService").invoke(null);Class.forName("android.app.IActivityTaskManager").getMethod("setFocusedTask",int.class).invoke(service,task);return true;}catch(Exception e){return false;}}
 static void run(String kind,String pkg,int display)throws Exception{
  if(!validPackage(pkg)||(display!=0&&display!=4))throw new IllegalArgumentException();
  String resolved=ActivityProbe.command("/system/bin/cmd","package","resolve-activity","--brief","--user","0","-a","android.intent.action.MAIN","-c","android.intent.category.LAUNCHER",pkg);
  String component=null;for(String line:resolved.split("\n"))if(line.trim().matches(Pattern.quote(pkg)+"/[A-Za-z0-9_.$]+"))component=line.trim();
  if(component==null)throw new IllegalStateException("App has no launcher activity");
  if(kind.equals("app_close")){
   if(pkg.equals("com.alan.thormonitor")||pkg.equals("com.android.systemui"))throw new IllegalArgumentException();
   if(rootFor(ActivityProbe.command("/system/bin/am","stack","list"),pkg)<0)throw new IllegalStateException("App is no longer open");
   ActivityProbe.command("/system/bin/am","force-stop","--user","0",pkg);return;
  }
  if(!kind.equals("app_open"))throw new IllegalArgumentException();
  String stacks=ActivityProbe.command("/system/bin/am","stack","list");int[] task=taskFor(stacks,pkg,display);
  if(task!=null){if(task[2]!=display){String moved=ActivityProbe.command("/system/bin/am","display","move-stack",String.valueOf(task[0]),String.valueOf(display));if(moved.contains("Error")||moved.contains("Exception"))throw new IllegalStateException("App cannot move between displays");}if(focusTask(task[1]))return;}
  String opened=ActivityProbe.command("/system/bin/am","start","--user","0","--display",String.valueOf(display),"--activity-reorder-to-front","-n",component);
  if(opened.contains("Error:")||opened.contains("Exception")||opened.contains("Permission Denial"))throw new IllegalStateException("App could not open on this display");
 }
}
