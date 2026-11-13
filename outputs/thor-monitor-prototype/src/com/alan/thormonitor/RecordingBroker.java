package com.alan.thormonitor;
import android.app.*;import android.content.*;import android.net.*;import android.os.*;import java.io.*;import org.json.*;
/** Host-side authenticated bridge; MP4 file descriptors keep the helper free for normal controls. */
final class RecordingBroker {
 private static PowerManager.WakeLock wake;
 private static LocalSocket connect(Context c,JSONObject request)throws Exception{
  LocalSocket socket=new LocalSocket();try{socket.connect(new LocalSocketAddress(ThorControls.socketName(c),LocalSocketAddress.Namespace.ABSTRACT));socket.setSoTimeout(20000);if(socket.getPeerCredentials().getUid()!=2000)throw new SecurityException();byte[] bytes=request.toString().getBytes("UTF-8");if(bytes.length>180)throw new IllegalArgumentException();DataOutputStream out=new DataOutputStream(socket.getOutputStream());out.writeShort(bytes.length);out.write(bytes);out.flush();return socket;}catch(Exception e){socket.close();throw e;}
 }
 private static void holdScreens(Context c){if(wake==null){wake=c.getSystemService(PowerManager.class).newWakeLock(PowerManager.SCREEN_BRIGHT_WAKE_LOCK|PowerManager.ACQUIRE_CAUSES_WAKEUP,"ThorMonitor:Recording");wake.setReferenceCounted(false);}if(!wake.isHeld())wake.acquire(210000);}
 static synchronized JSONObject request(Context c,String action,String token,int mode)throws Exception{return request(c,action,token,mode,1,60);}
 static synchronized JSONObject request(Context c,String action,String token,int mode,int quality,int fps)throws Exception{
  if(action.equals("record_start")){holdScreens(c);Thread.sleep(250);}
  try{return exchange(c,action,token,mode,quality,fps);}catch(Exception e){if(action.equals("record_start")&&wake!=null&&wake.isHeld())wake.release();throw e;}
 }
 private static JSONObject exchange(Context c,String action,String token,int mode,int quality,int fps)throws Exception{
  JSONObject body=new JSONObject().put("set",action).put("value",token).put("mode",mode).put("quality",quality).put("fps",fps);
  try(LocalSocket socket=connect(c,body)){DataInputStream in=new DataInputStream(socket.getInputStream());int n=in.readUnsignedShort();if(n>4096)throw new IOException("Recording reply too large");byte[] bytes=new byte[n];in.readFully(bytes);JSONObject data=new JSONObject(new String(bytes,"UTF-8"));if(!data.optBoolean("ok"))throw new IllegalStateException(data.optString("error","Update Thor Monitor and check Controls recovery"));data.remove("ok");
   if(action.equals("record_start")){String expected=data.optString("token");new Handler(Looper.getMainLooper()).postDelayed(()->new Thread(()->{try{request(c,"record_status",expected,0);}catch(Exception ignored){}},"ThorRecordingFinish").start(),183000);}
   if(data.optString("state").equals("recording")){holdScreens(c);NotificationManager nm=c.getSystemService(NotificationManager.class);Intent stop=new Intent(c,MonitorService.class).setAction("STOP_RECORDING");PendingIntent pending=PendingIntent.getService(c,25,stop,PendingIntent.FLAG_IMMUTABLE|PendingIntent.FLAG_UPDATE_CURRENT);nm.notify(25,new Notification.Builder(c,"monitor").setSmallIcon(android.R.drawable.presence_video_online).setContentTitle("Recording Thor screens").setContentText("Tap to stop. Save the recording in Screen capture on your phone.").setOngoing(true).setContentIntent(pending).addAction(new Notification.Action.Builder(null,"Stop recording",pending).build()).build());
   }else{if(wake!=null&&wake.isHeld())wake.release();c.getSystemService(NotificationManager.class).cancel(25);}return data;
  }
 }
 static void stopCurrentAsync(Context c){Context app=c.getApplicationContext();new Thread(()->stopCurrent(app),"ThorRecordingStop").start();}
 static void stopCurrent(Context c){try{JSONObject data=request(c,"record_status","",0);if(data.optString("state").equals("recording"))request(c,"record_stop",data.getString("token"),0);}catch(Exception ignored){}finally{if(wake!=null&&wake.isHeld())wake.release();c.getSystemService(NotificationManager.class).cancel(25);}}
 static final class Clip implements Closeable{final InputStream stream;final long size;Clip(InputStream in,long size){stream=in;this.size=size;}public void close()throws IOException{stream.close();}}
 static Clip open(Context c,String token,int screen)throws Exception{
  try(LocalSocket socket=connect(c,new JSONObject().put("set","record_file").put("value",token).put("mode",screen))){DataInputStream in=new DataInputStream(socket.getInputStream());if(in.readUnsignedByte()!=1)throw new IOException("Recording unavailable");FileDescriptor[] descriptors=socket.getAncillaryFileDescriptors();if(descriptors==null||descriptors.length!=1)throw new IOException("Recording descriptor missing");FileInputStream file=new FileInputStream(descriptors[0]);try{long size=in.readLong();if(size<128||size>ScreenRecording.MAX_BYTES)throw new IOException("Invalid recording size");return new Clip(file,size);}catch(Exception e){file.close();throw e;}}
 }
}
