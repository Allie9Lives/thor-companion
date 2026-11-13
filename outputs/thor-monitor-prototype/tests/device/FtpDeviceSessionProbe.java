package com.alan.thormonitor.tests;
import android.app.*;import android.os.*;import android.content.*;import java.io.*;import java.lang.reflect.*;import org.json.*;
/** External test harness reads credentials only through authorized run-as; never prints them. */
public class FtpDeviceSessionProbe extends Instrumentation {
 public void onCreate(Bundle b){super.onCreate(b);start();}
 public void onStart(){Bundle result=new Bundle();Context c=getTargetContext();File details=new File(c.getFilesDir(),"ftp-device-test.json"),done=new File(c.getFilesDir(),"ftp-device-test.done");Method command=null;
  try{
   done.delete();details.delete();c.startForegroundService(new Intent().setClassName(c,"com.alan.thormonitor.MonitorService"));Thread.sleep(1200);
   Class<?> type=c.getClassLoader().loadClass("com.alan.thormonitor.FtpAccess");command=type.getDeclaredMethod("command",Context.class,String.class,String.class);command.setAccessible(true);
   JSONObject data=(JSONObject)command.invoke(null,c,"ftp_start","device-test");try(FileOutputStream out=new FileOutputStream(details)){out.write(data.toString().getBytes("UTF-8"));}
   long deadline=android.os.SystemClock.elapsedRealtime()+120000;while(!done.exists()&&android.os.SystemClock.elapsedRealtime()<deadline)Thread.sleep(200);
   if(!done.exists())throw new IllegalStateException("Desktop FTPS check timed out");
   command.invoke(null,c,"ftp_stop","device-test-stop");result.putString("status","passed: FTPS server started and stopped on Android");finish(0,result);
  }catch(Throwable e){result.putString("error",e.toString()+(e.getCause()==null?"":" cause="+e.getCause()));finish(1,result);}finally{if(command!=null)try{command.invoke(null,c,"ftp_stop","cleanup");}catch(Exception ignored){}details.delete();done.delete();}
 }
}
