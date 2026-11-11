package com.alan.thormonitor.tests;
import android.app.*;import android.os.*;import android.content.*;import android.media.*;import org.json.*;import java.lang.reflect.*;
public class LocatorVolumeDeviceTest extends Instrumentation {
 public void onCreate(Bundle b){super.onCreate(b);start();}
 public void onStart(){Bundle result=new Bundle();Method set=null;Context c=getTargetContext();boolean started=false;try{
  Class<?> locator=c.getClassLoader().loadClass("com.alan.thormonitor.FindThor");set=locator.getDeclaredMethod("set",Context.class,boolean.class);set.setAccessible(true);
  Field ringing=locator.getDeclaredField("ringing");ringing.setAccessible(true);
  AudioManager audio=c.getSystemService(AudioManager.class);int prior=audio.getStreamVolume(AudioManager.STREAM_ALARM),media=audio.getStreamVolume(AudioManager.STREAM_MUSIC);boolean muted=audio.isStreamMute(AudioManager.STREAM_ALARM);
  set.invoke(null,c,true);started=true;Thread.sleep(300);
  if(!ringing.getBoolean(null)||audio.getStreamVolume(AudioManager.STREAM_ALARM)!=audio.getStreamMaxVolume(AudioManager.STREAM_ALARM))throw new AssertionError("Locator did not start at maximum alarm volume");
  audio.setStreamVolume(AudioManager.STREAM_ALARM,0,0);audio.setStreamVolume(AudioManager.STREAM_MUSIC,media==0?1:0,0);Thread.sleep(500);
  if(audio.getStreamVolume(AudioManager.STREAM_ALARM)!=audio.getStreamMaxVolume(AudioManager.STREAM_ALARM)||audio.isStreamMute(AudioManager.STREAM_ALARM)||audio.getStreamVolume(AudioManager.STREAM_MUSIC)!=media)throw new AssertionError("Volume change was not reversed");
  Class<?> controls=c.getClassLoader().loadClass("com.alan.thormonitor.ThorControls");Constructor<?> ctor=controls.getDeclaredConstructor(Context.class);ctor.setAccessible(true);Object target=ctor.newInstance(c);Method apply=controls.getDeclaredMethod("apply",byte[].class);apply.setAccessible(true);
  if((Boolean)apply.invoke(target,(Object)"{\"id\":\"locator-volume-test\",\"set\":\"volume\",\"value\":0,\"target\":\"both\"}".getBytes("UTF-8")))throw new AssertionError("Remote volume command accepted during locator");
  set.invoke(null,c,false);Thread.sleep(400);started=false;
  if(ringing.getBoolean(null)||audio.getStreamVolume(AudioManager.STREAM_ALARM)!=prior||audio.isStreamMute(AudioManager.STREAM_ALARM)!=muted||audio.getStreamVolume(AudioManager.STREAM_MUSIC)!=media)throw new AssertionError("Previous volume was not restored");
  result.putString("status","passed: maximum alarm, enforced alarm/media volume, rejected remote changes, dismissal restores volume");finish(0,result);
 }catch(Throwable e){result.putString("error",e.toString()+(e.getCause()==null?"":" cause="+e.getCause()));finish(1,result);}finally{if(started&&set!=null)try{set.invoke(null,c,false);}catch(Exception ignored){}}}
}
