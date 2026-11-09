package com.alan.thormonitor;

import android.app.*;
import android.content.*;
import android.media.*;
import android.os.*;
import java.util.concurrent.*;

/** User-triggered, bounded Tranquility locator sound. No permanent volume changes. */
final class FindThor {
    private static final Handler main=new Handler(Looper.getMainLooper());
    private static AudioTrack track;
    private static AudioManager audio;
    private static AudioFocusRequest focus;
    private static Context app;
    private static int oldVolume, maximum;
    private static boolean oldMute;
    private static long began, fadeBegan;
    private static float currentVolume,fadeFrom;
    private static boolean fadingOut;
    private static final Runnable fadeTick=new Runnable(){public void run(){if(!fadingOut||track==null)return;long elapsed=SystemClock.elapsedRealtime()-fadeBegan;if(elapsed>=220){finishStop(false);return;}track.setVolume(LocatorEnvelope.fadeOut(fadeFrom,elapsed));main.postDelayed(this,16);}};
    static void requestStop(){LocatorStopPanel.dismiss();if(fadingOut)return;if(track==null){finishStop(false);return;}ringing=false;MonitorService.locatorChanged();fadingOut=true;main.removeCallbacks(tick);fadeFrom=currentVolume;fadeBegan=SystemClock.elapsedRealtime();main.post(fadeTick);}
    private static PowerManager.WakeLock wake;
    static volatile boolean ringing;
    static float amplitude(long elapsed){return LocatorEnvelope.amplitude(elapsed);}
    private static final Runnable tick=new Runnable(){public void run(){
        if(!ringing || track==null)return;
        long elapsed=SystemClock.elapsedRealtime()-began;
        if(elapsed>=60000){requestStop();return;}
        currentVolume=amplitude(elapsed);track.setVolume(currentVolume);main.postDelayed(this,250);
    }};
    static void set(Context context,boolean enabled) throws Exception {
        FutureTask<Void> action=new FutureTask<>(()->{if(enabled)startNow(context.getApplicationContext());else requestStop();return null;});
        if(Looper.myLooper()==Looper.getMainLooper())action.run();else main.post(action);
        try{action.get(3,TimeUnit.SECONDS);}catch(ExecutionException e){throw new IllegalStateException(e.getCause().getMessage());}
        catch(TimeoutException e){action.cancel(false);throw new IllegalStateException("Find Thor did not respond");}
    }
    static void recoverVolume(Context context) {
        if(ringing||fadingOut)return;
        android.content.SharedPreferences prefs=context.getSharedPreferences("monitor",0);
        if(!prefs.getBoolean("find_restore_volume",false))return;
        AudioManager manager=context.getSystemService(AudioManager.class);
        if(manager.getStreamVolume(AudioManager.STREAM_ALARM)==prefs.getInt("find_alarm_max",-1)) {
            manager.setStreamVolume(AudioManager.STREAM_ALARM,prefs.getInt("find_alarm_volume",0),0);
            if(prefs.getBoolean("find_alarm_mute",false))manager.adjustStreamVolume(AudioManager.STREAM_ALARM,AudioManager.ADJUST_MUTE,0);
        }
        prefs.edit().remove("find_restore_volume").apply();
    }
    private static void startNow(Context context) {
        if(fadingOut)stopNow();
        if(ringing)return;
        recoverVolume(context);
        app=context;audio=context.getSystemService(AudioManager.class);
        AudioAttributes attributes=new AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build();
        focus=new AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT).setAudioAttributes(attributes)
            .setOnAudioFocusChangeListener(change->{if(change==AudioManager.AUDIOFOCUS_LOSS || change==AudioManager.AUDIOFOCUS_LOSS_TRANSIENT)stopNow();},main).build();
        if(audio.requestAudioFocus(focus)!=AudioManager.AUDIOFOCUS_REQUEST_GRANTED){audio=null;focus=null;throw new IllegalStateException("Audio is busy. Try Find Thor again");}
        oldVolume=audio.getStreamVolume(AudioManager.STREAM_ALARM);oldMute=audio.isStreamMute(AudioManager.STREAM_ALARM);
        maximum=audio.getStreamMaxVolume(AudioManager.STREAM_ALARM);
        try {
            int resource=context.getResources().getIdentifier("thor_locator","raw",context.getPackageName());
            short[] samples;
            try(java.io.DataInputStream input=new java.io.DataInputStream(context.getResources().openRawResource(resource))){
                byte[] header=new byte[44];input.readFully(header);
                if(header[0]!='R'||header[8]!='W'||header[36]!='d')throw new IllegalStateException("Invalid locator audio");
                int count=(header[40]&255)|((header[41]&255)<<8)|((header[42]&255)<<16)|((header[43]&255)<<24);
                if(count<2||count>512000||count%2!=0)throw new IllegalStateException("Invalid locator audio size");
                samples=new short[count/2];for(int i=0;i<samples.length;i++)samples[i]=Short.reverseBytes(input.readShort());
            }
            track=new AudioTrack.Builder().setAudioAttributes(attributes).setAudioFormat(new AudioFormat.Builder()
                .setSampleRate(22050).setEncoding(AudioFormat.ENCODING_PCM_16BIT).setChannelMask(AudioFormat.CHANNEL_OUT_MONO).build())
                .setBufferSizeInBytes(samples.length*2).setTransferMode(AudioTrack.MODE_STATIC).build();
            for(AudioDeviceInfo d:audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS))if(d.getType()==AudioDeviceInfo.TYPE_BUILTIN_SPEAKER){track.setPreferredDevice(d);break;}
            if(track.write(samples,0,samples.length)!=samples.length)throw new IllegalStateException("Could not prepare locator tone");
            track.setLoopPoints(0,samples.length,-1);currentVolume=amplitude(0);track.setVolume(currentVolume);
            context.getSharedPreferences("monitor",0).edit().putBoolean("find_restore_volume",true).putInt("find_alarm_volume",oldVolume).putInt("find_alarm_max",maximum).putBoolean("find_alarm_mute",oldMute).commit();
            audio.setStreamVolume(AudioManager.STREAM_ALARM,maximum,0);
            if(oldMute)audio.adjustStreamVolume(AudioManager.STREAM_ALARM,AudioManager.ADJUST_UNMUTE,0);
            wake=context.getSystemService(PowerManager.class).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK,"ThorMonitor:Find");wake.acquire(65000);
            began=SystemClock.elapsedRealtime();ringing=true;MonitorService.locatorChanged();track.play();main.post(tick);
            NotificationManager nm=context.getSystemService(NotificationManager.class);
            NotificationChannel channel=new NotificationChannel("find_thor","Find Thor",NotificationManager.IMPORTANCE_HIGH);
            channel.setSound(null,null);channel.enableVibration(false);nm.createNotificationChannel(channel);
            Intent stop=new Intent(context,MonitorService.class).setAction("STOP_FIND");
            PendingIntent pending=PendingIntent.getService(context,22,stop,PendingIntent.FLAG_IMMUTABLE|PendingIntent.FLAG_UPDATE_CURRENT);
            Notification note=new Notification.Builder(context,"find_thor").setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
                .setContentTitle("Finding your Thor").setContentText("Tap to stop the locator sound").setContentIntent(pending).setDeleteIntent(pending)
                .setAutoCancel(true).setTimeoutAfter(60000).addAction(new Notification.Action.Builder(null,"Stop sound",pending).build()).build();
            LocatorStopPanel.show(context);
            try{nm.notify(22,note);}catch(SecurityException ignored){} // Phone Stop and automatic timeout remain available.
        }catch(Exception e){stopNow();throw new IllegalStateException("Could not play locator sound");}
    }
    static void stopNow() {finishStop(true);}
    private static void finishStop(boolean removePanel) {
        boolean wasRinging=ringing;
        if(removePanel)LocatorStopPanel.hide();
        main.removeCallbacks(tick);main.removeCallbacks(fadeTick);fadingOut=false;ringing=false;if(wasRinging)MonitorService.locatorChanged();
        if(track!=null){try{track.stop();}catch(Exception ignored){}track.release();track=null;}
        if(audio!=null){
            if(audio.getStreamVolume(AudioManager.STREAM_ALARM)==maximum){audio.setStreamVolume(AudioManager.STREAM_ALARM,oldVolume,0);if(oldMute)audio.adjustStreamVolume(AudioManager.STREAM_ALARM,AudioManager.ADJUST_MUTE,0);}
            if(focus!=null)audio.abandonAudioFocusRequest(focus);
        }
        if(wake!=null && wake.isHeld())wake.release();wake=null;focus=null;audio=null;
        if(app!=null){app.getSharedPreferences("monitor",0).edit().remove("find_restore_volume").apply();app.getSystemService(NotificationManager.class).cancel(22);}
    }
}
