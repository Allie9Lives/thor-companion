package com.alan.thormonitor;
import android.app.*;import android.content.*;import android.content.pm.*;import android.database.Cursor;import android.net.Uri;import android.os.*;import java.io.*;import java.net.*;import java.security.*;import java.util.*;import java.util.concurrent.*;import org.json.*;
final class HostUpdates {
 private static final ExecutorService work=Executors.newSingleThreadExecutor();
 static volatile HostRelease latest;static volatile boolean busy;static volatile String status="Check GitHub for the latest host update.";
 static String installed(Context c){try{return c.getPackageManager().getPackageInfo(c.getPackageName(),0).versionName;}catch(Exception e){return "0.0.0";}}
 static synchronized void check(Context context,boolean force){
  Context c=context.getApplicationContext();if(busy)return;
  if(!force&&(!c.getSharedPreferences("monitor",0).getBoolean("updates_on_open",false)||System.currentTimeMillis()-c.getSharedPreferences("host_updates",0).getLong("checked",0)<6*3600000L))return;
  busy=true;status="Checking GitHub…";work.execute(()->{try{
   HttpURLConnection connection=(HttpURLConnection)new URL("https://api.github.com/repos/Allie9Lives/thor-companion/releases/latest").openConnection();connection.setConnectTimeout(12000);connection.setReadTimeout(12000);connection.setRequestProperty("Accept","application/vnd.github+json");connection.setRequestProperty("User-Agent","Thor-Monitor/"+installed(c));
   try{int code=connection.getResponseCode();if(code==403||code==429)throw new IOException("GitHub rate limit reached. Try again later.");if(code!=200)throw new IOException("GitHub is unavailable ("+code+").");ByteArrayOutputStream out=new ByteArrayOutputStream();try(InputStream in=connection.getInputStream()){byte[] buffer=new byte[8192];int count;while((count=in.read(buffer))!=-1){if(out.size()+count>2*1024*1024)throw new IOException("Release response is too large.");out.write(buffer,0,count);}}latest=HostRelease.parse(new JSONObject(out.toString("UTF-8")));}finally{connection.disconnect();}
   status=HostRelease.compare(latest.version,installed(c))>0?"Thor Monitor "+latest.version+" is available.":"You’re up to date.";c.getSharedPreferences("host_updates",0).edit().putLong("checked",System.currentTimeMillis()).apply();
  }catch(Exception e){status=e.getMessage()==null?"Could not check updates. Check your connection.":e.getMessage();}finally{busy=false;}});
 }
 static File apk(Context c){File dir=c.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS);return new File(dir==null?c.getCacheDir():dir,"thor-monitor-update.apk");}
 static synchronized void download(Context context){
  if(busy||latest==null)return;Context c=context.getApplicationContext();HostRelease item=latest;
  if(HostRelease.compare(item.version,installed(c))<=0){status="No newer host update is available.";return;}
  android.content.SharedPreferences p=c.getSharedPreferences("host_updates",0);if(p.getLong("download",-1)!=-1)return;
  try{File file=apk(c);if(file.exists()&&!file.delete())throw new IOException("Could not replace the previous download.");
   DownloadManager manager=c.getSystemService(DownloadManager.class);long id=manager.enqueue(new DownloadManager.Request(Uri.parse(item.url)).setTitle("Thor Monitor "+item.version).setDescription("Host update").setMimeType("application/vnd.android.package-archive").setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE).setDestinationUri(Uri.fromFile(file)));
   p.edit().putLong("download",id).putString("digest",item.digest).putLong("size",item.size).putString("version",item.version).putBoolean("verified",false).apply();status="Downloading Thor Monitor…";
  }catch(Exception e){status="Could not start the download. Check storage and try again.";}
 }
 static synchronized void poll(Context context){
  Context c=context.getApplicationContext();android.content.SharedPreferences p=c.getSharedPreferences("host_updates",0);long id=p.getLong("download",-1);if(id<0||busy)return;
  if(p.getBoolean("verified",false)){
   try{if(HostRelease.compare(p.getString("version","0.0.0"),installed(c))<=0){c.getSystemService(DownloadManager.class).remove(id);p.edit().remove("download").putBoolean("verified",false).apply();status="You’re up to date.";}}catch(Exception ignored){}return;
  }
  try(Cursor cursor=c.getSystemService(DownloadManager.class).query(new DownloadManager.Query().setFilterById(id))){
   if(cursor==null||!cursor.moveToFirst()){p.edit().remove("download").apply();status="Download no longer available. Try again.";return;}
   int state=cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS));
   if(state==DownloadManager.STATUS_FAILED){c.getSystemService(DownloadManager.class).remove(id);p.edit().remove("download").apply();status="Download failed. Check your connection and storage.";}
   else if(state==DownloadManager.STATUS_SUCCESSFUL){busy=true;status="Verifying update…";work.execute(()->{try{verify(c,apk(c),p.getString("digest",""),p.getLong("size",0),p.getString("version",""));p.edit().putBoolean("verified",true).apply();status="Update ready to install.";}catch(Exception e){c.getSystemService(DownloadManager.class).remove(id);p.edit().remove("download").putBoolean("verified",false).apply();status=e.getMessage()==null?"Could not verify the update.":e.getMessage();}finally{busy=false;}});}
   else {long downloaded=cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)),total=cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_TOTAL_SIZE_BYTES));status=state==DownloadManager.STATUS_PAUSED?"Download paused. Waiting for a connection…":total>0?"Downloading… "+(100*downloaded/total)+"%":"Downloading…";}
  }catch(Exception e){status="Could not read download status.";}
 }
 static void verify(Context c,File file,String expected,long size,String version)throws Exception{
  if(size<=0||file.length()!=size)throw new IOException("Update download is incomplete. Try again.");
  MessageDigest digest=MessageDigest.getInstance("SHA-256");try(InputStream in=new FileInputStream(file)){byte[] b=new byte[16384];int n;while((n=in.read(b))!=-1)digest.update(b,0,n);}StringBuilder hex=new StringBuilder();for(byte b:digest.digest())hex.append(String.format(java.util.Locale.US,"%02x",b&255));if(!hex.toString().equals(expected))throw new IOException("Update checksum did not match. Download it again.");
  PackageManager pm=c.getPackageManager();PackageInfo incoming=pm.getPackageArchiveInfo(file.getPath(),PackageManager.GET_SIGNING_CERTIFICATES),current=pm.getPackageInfo(c.getPackageName(),PackageManager.GET_SIGNING_CERTIFICATES);
  if(incoming==null||!c.getPackageName().equals(incoming.packageName)||!version.equals(incoming.versionName))throw new IOException("This APK is not the expected Thor Monitor update.");
  if(incoming.getLongVersionCode()<=current.getLongVersionCode())throw new IOException("This build is already installed or is older.");
  if(incoming.signingInfo==null||current.signingInfo==null||!new HashSet<>(Arrays.asList(incoming.signingInfo.getApkContentsSigners())).equals(new HashSet<>(Arrays.asList(current.signingInfo.getApkContentsSigners()))))throw new IOException("Update signing certificate does not match this installation.");
 }
 static void cancel(Context c){android.content.SharedPreferences p=c.getSharedPreferences("host_updates",0);long id=p.getLong("download",-1);if(id>=0)c.getSystemService(DownloadManager.class).remove(id);p.edit().remove("download").putBoolean("verified",false).apply();status="Download cancelled.";}
 static boolean ready(Context c){return c.getSharedPreferences("host_updates",0).getBoolean("verified",false)&&apk(c).isFile();}
 static boolean downloading(Context c){return c.getSharedPreferences("host_updates",0).getLong("download",-1)>=0&&!ready(c);}
 static void install(Activity a){
  if(!ready(a))return;
  if(!a.getPackageManager().canRequestPackageInstalls()){a.startActivity(new Intent(android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,Uri.parse("package:"+a.getPackageName())));return;}
  if(busy)return;busy=true;status="Verifying update…";Context c=a.getApplicationContext();
  work.execute(()->{try{
   android.content.SharedPreferences p=c.getSharedPreferences("host_updates",0);verify(c,apk(c),p.getString("digest",""),p.getLong("size",0),p.getString("version",""));
   Uri uri=c.getSystemService(DownloadManager.class).getUriForDownloadedFile(p.getLong("download",-1));if(uri==null)throw new IOException("Download no longer available. Try again.");
   new Handler(Looper.getMainLooper()).post(()->{if(a.isFinishing()||a.isDestroyed())return;try{a.startActivity(new Intent(Intent.ACTION_VIEW).setDataAndType(uri,"application/vnd.android.package-archive").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION));status="Update ready to install.";}catch(ActivityNotFoundException e){status="Android’s package installer is unavailable.";}});
  }catch(Exception e){status=e.getMessage()==null?"Could not verify the update.":e.getMessage();c.getSharedPreferences("host_updates",0).edit().putBoolean("verified",false).remove("download").apply();}finally{busy=false;}});
 }

 static void obtainium(Activity a){try{Uri uri=Uri.parse("obtainium://app/"+Uri.encode(HostRelease.obtainiumConfig().toString()));a.startActivity(new Intent(Intent.ACTION_VIEW,uri));}catch(Exception e){new AlertDialog.Builder(a).setTitle("Add to Obtainium").setMessage("Install Obtainium, then return here to add Thor Monitor.").setPositiveButton("Get Obtainium",(d,w)->open(a,"https://obtainium.imranr.dev/")).setNeutralButton("Copy GitHub URL",(d,w)->{a.getSystemService(android.content.ClipboardManager.class).setPrimaryClip(ClipData.newPlainText("Thor Monitor",HostRelease.REPO));android.widget.Toast.makeText(a,"GitHub URL copied",android.widget.Toast.LENGTH_SHORT).show();}).setNegativeButton("Cancel",null).show();}}
 static void open(Activity a,String url){try{a.startActivity(new Intent(Intent.ACTION_VIEW,Uri.parse(url)));}catch(ActivityNotFoundException e){android.widget.Toast.makeText(a,"No browser available",android.widget.Toast.LENGTH_SHORT).show();}}
}
