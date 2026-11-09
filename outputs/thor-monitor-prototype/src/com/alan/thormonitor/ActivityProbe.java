package com.alan.thormonitor;
import java.io.*;import java.util.*;import java.util.concurrent.*;import java.util.regex.*;import org.json.*;
/** Fixed read-only shell probe. CPU is normalized across all cores; GPU attribution is unavailable. */
final class ActivityProbe {
 private static long lastTotal;private static final Map<String,Long> lastCpu=new HashMap<>();
 static String command(String... args)throws Exception{
  java.lang.Process p=new ProcessBuilder(args).redirectErrorStream(true).start();
  ScheduledExecutorService killer=Executors.newSingleThreadScheduledExecutor();killer.schedule(()->p.destroyForcibly(),3,TimeUnit.SECONDS);
  try(InputStream in=p.getInputStream()){ByteArrayOutputStream bytes=new ByteArrayOutputStream();byte[] buffer=new byte[8192];int n;while((n=in.read(buffer))!=-1){if(bytes.size()+n>512*1024)throw new IOException("Probe too large");bytes.write(buffer,0,n);}if(!p.waitFor(1,TimeUnit.SECONDS)||p.exitValue()!=0)throw new IOException("Probe unavailable");return bytes.toString("UTF-8");}finally{p.destroy();killer.shutdownNow();}
 }
 static String read(File file,int cap)throws Exception{try(InputStream in=new FileInputStream(file)){byte[] b=new byte[cap];int n=in.read(b);return n<0?"":new String(b,0,n,"UTF-8");}}
 static synchronized JSONObject sample()throws Exception{
  String input=command("/system/bin/dumpsys","input");
  JSONObject result=new JSONObject();Matcher lid=Pattern.compile("Device \\d+: hall_switch[\\s\\S]*?SwitchValues: ([0-9a-fA-F]+)").matcher(input);
  result.put("lid",lid.find()?((Long.parseLong(lid.group(1),16)&1)!=0):JSONObject.NULL);
  Map<Integer,String> focused=new LinkedHashMap<>();Matcher app=Pattern.compile("displayId=(\\d+), name='ActivityRecord\\{[^ ]+ u\\d+ ([A-Za-z0-9_.]+)/").matcher(input);
  while(app.find()&&focused.size()<2)focused.put(Integer.parseInt(app.group(1)),app.group(2));
  long total=0;String[] ticks=read(new File("/proc/stat"),4096).split("\\n")[0].trim().split("\\s+");for(int i=1;i<Math.min(9,ticks.length);i++)total+=Long.parseLong(ticks[i]);
  Map<String,Long> sums=new HashMap<>();for(String pkg:focused.values())sums.put(pkg,0L);
  File[] proc=new File("/proc").listFiles();if(proc!=null)for(File dir:proc){if(!dir.getName().matches("[0-9]+"))continue;try{String name=read(new File(dir,"cmdline"),512).split("\u0000",2)[0].split(":",2)[0];if(!focused.containsValue(name))continue;String stat=read(new File(dir,"stat"),4096);String[] fields=stat.substring(stat.lastIndexOf(')')+2).split(" ");long cpu=Long.parseLong(fields[11])+Long.parseLong(fields[12]);sums.put(name,sums.get(name)+cpu);}catch(Exception ignored){}}
  JSONArray apps=new JSONArray();for(Map.Entry<Integer,String> entry:focused.entrySet()){String pkg=entry.getValue();Long previous=lastCpu.get(pkg);long current=sums.get(pkg);Object cpu=previous!=null&&lastTotal>0&&total>lastTotal&&current>=previous?Math.round(10000.0*(current-previous)/(total-lastTotal))/100.0:JSONObject.NULL;apps.put(new JSONObject().put("p",pkg).put("d",entry.getKey()).put("cpu",cpu));}
  lastTotal=total;lastCpu.clear();lastCpu.putAll(sums);return result.put("apps",apps);
 }
}
