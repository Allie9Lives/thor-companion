package com.alan.thormonitor;
import android.content.*;import android.os.*;import android.os.storage.*;import java.io.*;import java.nio.file.*;import java.util.*;import org.json.*;
/** Optional user-granted shared storage roots. Never uses shell/root privileges for files. */
final class SharedFiles {
 static boolean enabled(Context c){return Environment.isExternalStorageManager()&&c.getSharedPreferences("monitor",0).getBoolean("files_full",false);}
 static Map<String,File> roots(Context c){Map<String,File> roots=new LinkedHashMap<>();if(!enabled(c))return roots;roots.put("internal",Environment.getExternalStorageDirectory());for(StorageVolume v:c.getSystemService(StorageManager.class).getStorageVolumes())if(!v.isPrimary()&&v.isRemovable()&&Telemetry.isSdVolume(v)&&v.getDirectory()!=null&&(v.getState().equals(Environment.MEDIA_MOUNTED)||v.getState().equals(Environment.MEDIA_MOUNTED_READ_ONLY))){roots.put("sd",v.getDirectory());break;}return roots;}
 static File resolve(File root,String path)throws Exception{
  File file=root;for(String part:FileAccess.segments(path))file=new File(file,part);
  File base=root.getCanonicalFile(),target=file.getCanonicalFile();String prefix=base.getPath()+File.separator;
  if(!target.equals(base)&&!target.getPath().startsWith(prefix))throw new SecurityException("Outside shared storage");
  String relative=target.equals(base)?"":target.getPath().substring(prefix.length());
  if(relative.equals("Android/data")||relative.startsWith("Android/data/")||relative.equals("Android/obb")||relative.startsWith("Android/obb/"))throw new SecurityException("Android protects other apps' private files");return target;
 }
 static void serve(Context c,String method,String route,Map<String,String> q,InputStream in,OutputStream out,Map<String,String> headers)throws Exception{
  Map<String,File> roots=roots(c);
  if(method.equals("GET")&&route.equals("/v1/roots")){JSONArray a=new JSONArray();for(String id:roots.keySet())a.put(new JSONObject().put("id",id).put("name",id.equals("sd")?"microSD storage":"Internal storage"));FileAccess.json(out,200,new JSONObject().put("roots",a).put("full",true));return;}
  File base=roots.get(q.getOrDefault("root",""));if(base==null)throw new IllegalArgumentException("Storage is unavailable");File file=resolve(base,q.getOrDefault("path",""));
  if(method.equals("GET")&&route.equals("/v1/list")){
   int offset=Integer.parseInt(q.getOrDefault("offset","0"));if(offset<0||offset>1000000)throw new IllegalArgumentException();File[] children=file.listFiles();if(children==null)throw new SecurityException("This directory is protected or unavailable");Arrays.sort(children,Comparator.comparing(f->f.getName().toLowerCase(Locale.ROOT)));
   JSONArray rows=new JSONArray();int end=Math.min(children.length,offset+200);for(int i=offset;i<end;i++){File f=children[i];rows.put(new JSONObject().put("name",f.getName()).put("dir",f.isDirectory()).put("size",f.isDirectory()?JSONObject.NULL:f.length()).put("modified",f.lastModified()));}FileAccess.json(out,200,new JSONObject().put("entries",rows).put("next",end<children.length?end:-1));return;
  }
  if(method.equals("GET")&&route.equals("/v1/file")){
   if(!file.isFile()||!file.canRead())throw new FileNotFoundException("File is unavailable");long size=file.length();if(size>FileAccess.MAX_FILE)throw new IllegalArgumentException("File exceeds 64 GiB");try(InputStream stream=new FileInputStream(file)){FileAccess.reply(out,200,"application/octet-stream",size);FileAccess.copy(stream,out,size);}return;
  }
  if(method.equals("PUT")&&route.equals("/v1/file")){
   if(!file.isDirectory())throw new FileNotFoundException("Folder is unavailable");String name=q.getOrDefault("name","");FileAccess.validateName(name);String parent=q.getOrDefault("path","");File target=resolve(base,parent.isEmpty()?name:parent+"/"+name);
   if(target.exists()){FileAccess.json(out,409,new JSONObject().put("error","A file with this name already exists. Rename it before uploading."));return;}
   long size=Long.parseLong(headers.getOrDefault("content-length","-1"));if(size<0||size>FileAccess.MAX_FILE)throw new IllegalArgumentException("File exceeds 64 GiB");
   File temp=File.createTempFile(".thor-upload-",".part",file);try{try(FileOutputStream stream=new FileOutputStream(temp)){FileAccess.copy(in,stream,size);stream.getFD().sync();}Files.move(temp.toPath(),target.toPath());FileAccess.json(out,200,new JSONObject().put("ok",true).put("bytes",size));}finally{temp.delete();}return;
  }
  FileAccess.json(out,404,new JSONObject().put("error","Unknown file operation"));
 }
}
