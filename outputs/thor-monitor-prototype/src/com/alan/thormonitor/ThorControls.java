package com.alan.thormonitor;

import android.content.*;
import android.app.KeyguardManager;
import android.net.LocalSocket;
import android.net.LocalSocketAddress;
import java.io.*;
import android.hardware.display.DisplayManager;
import android.media.AudioManager;
import android.os.*;
import android.provider.Settings;
import android.view.Display;
import org.json.*;

/** Firmware-specific, allowlisted controls. No shell execution or arbitrary setting writes. */
final class ThorControls {
    private final Context context;
    private final ContentResolver resolver;
    private final AudioManager audio;
    private String lastId = "", lastError = "";
    private volatile CaptureBuffer shot;
    private JSONObject historyPage;
    synchronized void clearHistoryReply(){historyPage=null;}
    synchronized JSONObject readSnapshot(){if(historyPage!=null){JSONObject page=historyPage;historyPage=null;return page;}return snapshot();}
    private boolean streamRequested;
    private final Handler shotHandler=new Handler(Looper.getMainLooper());
    private final Runnable expireShot=()->clearShot();
    synchronized CaptureBuffer screenshot(){return shot;}
    synchronized boolean takeStreamRequest(){boolean value=streamRequested;streamRequested=false;return value;}
    synchronized void clearShot(){shot=null;streamRequested=false;shotHandler.removeCallbacks(expireShot);}
    byte[] captureImage(int mode) throws Exception {
        if(context.getSystemService(KeyguardManager.class).isKeyguardLocked() || !context.getSystemService(PowerManager.class).isInteractive())
            throw new IllegalStateException("Open and unlock the Thor to capture its screens");
        try(LocalSocket socket=new LocalSocket()) {
            socket.connect(new LocalSocketAddress(socketName(context),LocalSocketAddress.Namespace.ABSTRACT));socket.setSoTimeout(20000);
            if(socket.getPeerCredentials().getUid()!=2000)throw new SecurityException("Controls helper unavailable");
            byte[] request=new JSONObject().put("set","capture").put("value",mode).toString().getBytes("UTF-8");
            DataOutputStream out=new DataOutputStream(socket.getOutputStream());out.writeShort(request.length);out.write(request);out.flush();
            DataInputStream in=new DataInputStream(socket.getInputStream());int size=in.readInt();
            if(size<10 || size>ScreenCapture.MAX_BYTES)throw new IOException("Capture failed; check automatic recovery or restart the Thor after updating");
            byte[] bytes=new byte[size];in.readFully(bytes);return bytes;
        }
    }
    ThorControls(Context c) { context=c; resolver=c.getContentResolver(); audio=c.getSystemService(AudioManager.class); }
    static synchronized String socketName(Context c) throws Exception {
        File file=new File(c.getFilesDir(),"control-socket");
        if(!file.exists()) {
            String name="thor-controls-"+java.util.UUID.randomUUID().toString().replace("-","");
            try(FileOutputStream out=c.openFileOutput("control-socket",Context.MODE_PRIVATE)) { out.write(name.getBytes("UTF-8")); }
        }
        try(BufferedReader reader=new BufferedReader(new FileReader(file))) { return reader.readLine(); }
    }
    static JSONObject helperStatus(Context context) {
        try(LocalSocket socket=new LocalSocket()) {
            socket.connect(new LocalSocketAddress(socketName(context),LocalSocketAddress.Namespace.ABSTRACT));socket.setSoTimeout(1000);
            if(socket.getPeerCredentials().getUid()!=2000)return new JSONObject();
            byte[] bytes="{\"set\":\"ping\",\"value\":0}".getBytes("UTF-8");
            DataOutputStream out=new DataOutputStream(socket.getOutputStream());out.writeShort(bytes.length);out.write(bytes);out.flush();
            DataInputStream in=new DataInputStream(socket.getInputStream());int size=in.readUnsignedShort();if(size>512)return new JSONObject();
            byte[] response=new byte[size];in.readFully(response);
            return new JSONObject(new String(response,"UTF-8")).put("peer_pid",socket.getPeerCredentials().getPid());
        }catch(Exception e){return new JSONObject();}
    }
    boolean helperReady() { JSONObject status=helperStatus(context);return status.optBoolean("ok")&&status.optInt("protocol")>=5; }
    static int outdatedHelperPid(Context c){JSONObject status=helperStatus(c);return status.optBoolean("ok")&&status.optInt("protocol")<5?status.optInt("peer_pid",0):0;}
    private boolean helper(String command,int value) {
        try(LocalSocket socket=new LocalSocket()) {
            socket.connect(new LocalSocketAddress(socketName(context),LocalSocketAddress.Namespace.ABSTRACT));
            socket.setSoTimeout(4000);
            if(socket.getPeerCredentials().getUid()!=2000) return false;
            byte[] bytes=new JSONObject().put("set",command).put("value",value).toString().getBytes("UTF-8");
            DataOutputStream out=new DataOutputStream(socket.getOutputStream());out.writeShort(bytes.length);out.write(bytes);out.flush();
            DataInputStream in=new DataInputStream(socket.getInputStream());int length=in.readUnsignedShort();if(length>256)return false;
            byte[] response=new byte[length];in.readFully(response);return new JSONObject(new String(response,"UTF-8")).optBoolean("ok");
        } catch(Exception e) { return false; }
    }
    private int bottom() {
        for (Display d : context.getSystemService(DisplayManager.class).getDisplays())
            if (d.getDisplayId()!=Display.DEFAULT_DISPLAY && internal(d)) return d.getDisplayId();
        return -1;
    }
    private boolean internal(Display d) {
        try { return ((Integer)Display.class.getDeclaredMethod("getType").invoke(d))==1; }
        catch(Exception e) { return false; }
    }
    private int brightness(int display, Integer value) throws Exception {
        if (display < 0) throw new IllegalStateException("Screen unavailable");
        IBinder binder=(IBinder)Class.forName("android.os.ServiceManager").getDeclaredMethod("getService",String.class).invoke(null,"SettingsController");
        if (binder==null) throw new IllegalStateException("Thor display controller unavailable");
        Parcel in=Parcel.obtain(), out=Parcel.obtain();
        try {
            in.writeInt(display);
            if (value!=null) { in.writeInt(value); in.writeBoolean(false); }
            if (!binder.transact(value==null?16388:16386,in,out,0)) throw new IllegalStateException("Unsupported display firmware");
            out.readException(); return out.readInt();
        } finally { in.recycle(); out.recycle(); }
    }
    private int get(String key) { return Settings.System.getInt(resolver,key,-1); }
    private void put(String command,int value) {
        if(!helper(command,value)) throw new IllegalStateException("Check Automatic recovery setup in Thor Monitor");
        String setting=ControlHelper.setting(command,value);
        if(get(setting)!=value) throw new IllegalStateException("Setting was rejected");
    }
    void holdSecondaryVolume(int value){if(FindThor.volumeLocked()&&get("secondary_screen_volume_level")!=value)helper("volume",value);}
    private int pct(int n,int max) { return Math.round(100f*n/max); }
    synchronized JSONObject snapshot() {
        JSONObject j=new JSONObject();
        try {
            j.put("v",1).put("settings",helperReady()).put("power_control",helperReady()).put("finder",true).put("find",FindThor.ringing?1:0).put("history",true);
            JSONObject rest=PowerSaving.snapshot(context);for(java.util.Iterator<String> keys=rest.keys();keys.hasNext();){String key=keys.next();j.put(key,rest.get(key));}
            j.put("wake_control",true).put("screens_awake",context.getSystemService(PowerManager.class).isInteractive());
            j.put("screenshots",false).put("wifi_screenshots",true);
            if(shot!=null)j.put("shot_token",Integer.toUnsignedString(shot.token)).put("shot_bytes",shot.bytes.length).put("shot_crc",shot.crc);
            j.put("files",true).put("activity",true);
            j.put("keyboard",true).put("keyboard_selected",RemoteKeyboard.selected(context)).put("keyboard_focused",RemoteKeyboard.focused());
            try { j.put("bt",pct(brightness(0,null),255)).put("bb",pct(brightness(bottom(),null),255)); }
            catch(Exception e) { j.put("brightness_error","Display control unavailable on this firmware"); }
            int max=audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC);
            j.put("vt",pct(audio.getStreamVolume(AudioManager.STREAM_MUSIC),max));
            int b=get("secondary_screen_volume_level");
            j.put("vb",b<0?JSONObject.NULL:pct(b,max));
            j.put("hz",Math.round(Settings.System.getFloat(resolver,"peak_refresh_rate",60)));
            j.put("fan",get("fan_mode")).put("performance",get("performance_mode"));
            j.put("bypass",get("is_charging_separation")).put("focus",get("screen_focus_lock"));
            j.put("vibration",Settings.System.getInt(resolver,"vibrate_on",1)).put("style",get("temp_abxy_layout_mode"));
            String led=Settings.System.getString(resolver,"joystick_light_enabled");
            j.put("led", "1,1".equals(led)?1:"0,0".equals(led)?0:-1);
            j.put("ack",lastId).put("error",lastError);
        } catch(Exception e) { try { j.put("error","Could not read controls"); } catch(Exception ignored) {} }
        return j;
    }
    private final CommandReplay replay=new CommandReplay();
    synchronized JSONObject exchange(byte[] bytes){apply(bytes);return readSnapshot();}
    synchronized boolean apply(byte[] bytes) {
        String id;
        try {
            if(bytes==null||bytes.length>180)throw new IllegalArgumentException("Command too long");
            id=new JSONObject(new String(bytes,java.nio.charset.StandardCharsets.UTF_8)).getString("id");
            if(!id.matches("[a-zA-Z0-9_-]{1,32}"))throw new IllegalArgumentException("Invalid request ID");
            String prior=replay.find(id,bytes,android.os.SystemClock.elapsedRealtime());
            if(prior!=null){historyPage=new JSONObject(prior);return historyPage.optString("error","").isEmpty();}
        }catch(Exception e){historyPage=new JSONObject();try{historyPage.put("ack","").put("error","Invalid or reused request ID");}catch(Exception ignored){}return false;}
        boolean ok=execute(bytes);
        replay.save(id,bytes,(historyPage!=null?historyPage:snapshot()).toString(),android.os.SystemClock.elapsedRealtime());
        return ok;
    }
    private boolean execute(byte[] bytes) {
        try {
            if (bytes.length>180) throw new IllegalArgumentException("Command too long");
            JSONObject j=new JSONObject(new String(bytes,java.nio.charset.StandardCharsets.UTF_8));
            String id=j.getString("id");
            if (!id.matches("[a-zA-Z0-9_-]{1,32}")) throw new IllegalArgumentException("Invalid request ID");
            lastId=id; lastError="";
            String key=j.getString("set"), target=j.optString("target","");
            Object raw=j.get("value");
            historyPage=null;
            if(key.equals("network_session")) {
                if(!(raw instanceof Number)||((Number)raw).doubleValue()!=1)throw new IllegalArgumentException("Invalid network session");
                historyPage=FileAccess.networkSession(context,id);return true;
            }
            if(key.equals("files_session")) {
                if(!(raw instanceof Number)||((Number)raw).intValue()!=1||((Number)raw).doubleValue()!=1)throw new IllegalArgumentException("Invalid file session");
                historyPage=FileAccess.session(context,id);return true;
            }
            if(key.equals("activity")) {
                if(!(raw instanceof Number)||((Number)raw).doubleValue()!=0)throw new IllegalArgumentException("Invalid activity request");
                if(MonitorService.activity==null)throw new IllegalStateException("Start monitoring first");historyPage=MonitorService.activity.reply(id);return true;
            }
            if(key.equals("battery_sleep")) {
                if(!(raw instanceof Number)||((Number)raw).doubleValue()!=((Number)raw).longValue())throw new IllegalArgumentException("History cursor required");historyPage=BatteryHistory.get(context).sleepPage(((Number)raw).longValue(),id);return true;
            }
            if(key.equals("battery_history")) {
                if(!(raw instanceof Number) || ((Number)raw).doubleValue()!=((Number)raw).longValue())throw new IllegalArgumentException("History cursor required");
                historyPage=BatteryHistory.get(context).page(((Number)raw).longValue(),target,id);return true;
            }
            if(key.equals("screenshot_stream") || key.equals("screenshot_clear")) {
                if(key.equals("screenshot_clear") && shot==null)return true;
                if(key.equals("screenshot_stream"))throw new IllegalStateException("Screenshot transfer requires Wi-Fi");
                if(shot==null || !Integer.toUnsignedString(shot.token).equals(target))throw new IllegalStateException("Screenshot expired; capture again");
                if(key.equals("screenshot_clear"))clearShot();else streamRequested=true;
                return true;
            }
            if(key.equals("text") || key.equals("key")) {
                if(!(raw instanceof String)) throw new IllegalArgumentException("Keyboard text required");
                RemoteKeyboard.input(context,key,(String)raw);
                // Never record typed text, including in diagnostics or readback.
                return true;
            }
            if (!(raw instanceof Number) || ((Number)raw).doubleValue()!=((Number)raw).intValue()) throw new IllegalArgumentException("Integer value required");
            int value=((Number)raw).intValue();
            switch(key) {
                case "find":
                    range(value,0,1);FindThor.set(context,value==1);return true;
                case "power":
                    range(value,0,4);
                    if(value==3||value==4)MonitorService.restPower(value);
                    if(!helper("power",value==4?0:value))throw new IllegalStateException("Power control unavailable. Check automatic recovery");
                    return true;
                case "sleep_end":range(value,0,1439);if(value==context.getSharedPreferences("monitor",0).getInt("rest_start",1260))throw new IllegalArgumentException("Start and restore times must differ");context.getSharedPreferences("monitor",0).edit().putInt("rest_end",value).apply();MonitorService.restChanged();return true;
                case "screenshot":
                    throw new IllegalStateException("Screenshots now require Wi-Fi. Open Screenshots in the updated companion.");
                case "brightness":
                    range(value,0,100); target(target);
                    int bright=Math.max(1,Math.round(value*255f/100));
                    if (!target.equals("bottom")) brightness(0,bright);
                    if (!target.equals("top")) brightness(bottom(),bright);
                    break;
                case "volume":
                    if(FindThor.volumeLocked())throw new IllegalStateException("Volume is locked while Find my Thor is playing. Stop the sound first.");
                    range(value,0,100); target(target);
                    int volume=Math.round(value*audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)/100f);
                    if (!target.equals("top")) put("volume",volume);
                    if (!target.equals("bottom")) audio.setStreamVolume(AudioManager.STREAM_MUSIC,volume,0);
                    break;
                case "hz":
                    if(value!=60 && value!=120) throw new IllegalArgumentException("Choose 60 or 120 Hz");
                    boolean supported=false;
                    for(Display.Mode mode: context.getSystemService(DisplayManager.class).getDisplay(0).getSupportedModes())
                        if(Math.abs(mode.getRefreshRate()-value)<1) supported=true;
                    if(!supported) throw new IllegalArgumentException("Refresh rate unsupported");
                    put("hz",value);
                    break;
                case "fan":
                    if(value!=0 && value!=1 && value!=4 && value!=5) throw new IllegalArgumentException("Unsupported fan mode");
                    put("fan",value); break;
                case "performance": range(value,0,2); put("performance",value); break;
                case "focus": range(value,0,2); put("focus",value); break;
                case "bypass": range(value,0,1); put("bypass",value); break;
                case "vibration": range(value,0,1); put("vibration",value); break;
                case "style":
                    range(value,0,2);
                    if(!helper("style",value)) throw new IllegalStateException("Check Automatic recovery setup in Thor Monitor");
                    break;
                case "clean":
                    range(value,0,0);
                    if(!helper("clean",0)) throw new IllegalStateException("Background cleanup failed; check advanced controls");
                    break;
                case "led":
                    range(value,0,1);
                    if(!helper("led",value)) throw new IllegalStateException("Check Automatic recovery setup in Thor Monitor");
                    break;
                default: throw new IllegalArgumentException("Unsupported control");
            }
            Telemetry.log(context,"control_applied",new JSONObject().put("control",key).put("value",value));
            return true;
        } catch(Exception e) {
            lastError="Control failed: "+e.getMessage();
            if(lastError.length()>140) lastError=lastError.substring(0,140);
            Telemetry.log(context,"control_error",snapshot()); return false;
        }
    }
    private static void range(int value,int min,int max) { if(value<min || value>max) throw new IllegalArgumentException("Value out of range"); }
    private static void target(String t) { if(!t.equals("top") && !t.equals("bottom") && !t.equals("both")) throw new IllegalArgumentException("Unknown screen"); }
}
