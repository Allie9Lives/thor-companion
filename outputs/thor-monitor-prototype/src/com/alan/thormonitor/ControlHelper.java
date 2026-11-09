package com.alan.thormonitor;

import android.net.LocalServerSocket;
import android.net.LocalSocket;
import android.os.Process;
import org.json.JSONObject;
import java.io.*;
import java.nio.charset.StandardCharsets;

/** Optional ADB-started shell helper. Accepts only this app UID and fixed Thor settings. */
public final class ControlHelper {
    static String setting(String command,int v) {
        switch(command) {
            case "volume": if(v>=0 && v<=15) return "secondary_screen_volume_level"; break;
            case "hz": if(v==60 || v==120) return "peak_refresh_rate"; break;
            case "fan": if(v==0 || v==1 || v==4 || v==5) return "fan_mode"; break;
            case "performance": if(v>=0 && v<=2) return "performance_mode"; break;
            case "focus": if(v>=0 && v<=2) return "screen_focus_lock"; break;
            case "bypass": if(v==0 || v==1) return "is_charging_separation"; break;
            case "vibration": if(v==0 || v==1) return "vibrate_on"; break;
            case "led": if(v==0 || v==1) return "joystick_light_enabled"; break;
        }
        throw new IllegalArgumentException("Unsupported control or value");
    }
    static void write(String key,String value) throws Exception {
        java.lang.Process p=new ProcessBuilder("/system/bin/settings","put","system",key,value).redirectErrorStream(true).start();
        byte[] output=new byte[512];
        if(!p.waitFor(3,java.util.concurrent.TimeUnit.SECONDS)) { p.destroyForcibly(); throw new IOException("System setting timed out"); }
        int read=p.getInputStream().read(output);
        if(p.exitValue()!=0 || read>0) throw new IOException("System setting rejected");
    }
    public static void main(String[] args) throws Exception {
        if(Process.myUid()!=2000 || args.length!=2 || !args[0].matches("thor-controls-[a-f0-9]{32}")) throw new SecurityException("ADB shell startup required");
        final int owner=Integer.parseInt(args[1]);
        if(owner<10000) throw new SecurityException("Application UID required");
        try(LocalServerSocket server=new LocalServerSocket(args[0])) {
            while(true) {
                try(LocalSocket socket=server.accept()) {
                    socket.setSoTimeout(3000);
                    if(socket.getPeerCredentials().getUid()!=owner) continue;
                    DataInputStream in=new DataInputStream(socket.getInputStream());
                    int length=in.readUnsignedShort();
                    if(length>180) continue;
                    byte[] bytes=new byte[length];in.readFully(bytes);
                    JSONObject j=new JSONObject(new String(bytes,StandardCharsets.UTF_8));
                    if("activity".equals(j.optString("set"))) {
                        JSONObject observed;
                        try{observed=ActivityProbe.sample().put("ok",true);}catch(Exception e){observed=new JSONObject().put("ok",false);}
                        byte[] response=observed.toString().getBytes(StandardCharsets.UTF_8);
                        DataOutputStream reply=new DataOutputStream(socket.getOutputStream());reply.writeShort(response.length);reply.write(response);reply.flush();continue;
                    }
                    if("wifi_identity".equals(j.optString("set"))) {
                        JSONObject observed;try{observed=WifiTrustProbe.sample();}catch(Exception e){observed=new JSONObject().put("ok",false);}
                        byte[] response=observed.toString().getBytes(StandardCharsets.UTF_8);DataOutputStream reply=new DataOutputStream(socket.getOutputStream());reply.writeShort(response.length);reply.write(response);reply.flush();continue;
                    }
                    if("capture".equals(j.optString("set"))) {
                        DataOutputStream out=new DataOutputStream(socket.getOutputStream());
                        try { Object raw=j.get("value");
                            if(!(raw instanceof Number) || ((Number)raw).doubleValue()!=((Number)raw).intValue())throw new IllegalArgumentException();
                            byte[] image=ScreenCapture.capture(((Number)raw).intValue());out.writeInt(image.length);out.write(image);out.flush();
                        }catch(Exception e){out.writeInt(-1);out.flush();}
                        continue;
                    }
                    if("power".equals(j.optString("set"))) {
                        boolean ok=false;String[] command=null;
                        try {Object value=j.get("value");if(!(value instanceof Number)||((Number)value).doubleValue()!=((Number)value).intValue())throw new IllegalArgumentException();command=DevicePower.command(((Number)value).intValue());ok=true;}catch(Exception ignored){}
                        byte[] reply=new JSONObject().put("ok",ok).put("error",ok?"":"Unsupported power action").toString().getBytes(StandardCharsets.UTF_8);
                        DataOutputStream out=new DataOutputStream(socket.getOutputStream());out.writeShort(reply.length);out.write(reply);out.flush();
                        if(ok){final String[] fixed=command;new Thread(()->{try{Thread.sleep(1000);new ProcessBuilder(fixed).redirectOutput(new File("/dev/null")).redirectError(new File("/dev/null")).start();}catch(Exception ignored){}},"ThorPower").start();}
                        continue;
                    }
                    String error="";
                    try {
                        String command=j.getString("set");
                        Object rawValue=j.get("value");
                        if(!(rawValue instanceof Number) || ((Number)rawValue).doubleValue()!=((Number)rawValue).intValue()) throw new IllegalArgumentException("Integer required");
                        if(command.equals("clean") && j.getInt("value")!=0) throw new IllegalArgumentException("Invalid cleanup request");
                        if(command.equals("clean")) {
                            java.lang.Process clean=new ProcessBuilder("/system/bin/am","kill-all").redirectErrorStream(true).start();
                            if(!clean.waitFor(3,java.util.concurrent.TimeUnit.SECONDS)) {clean.destroyForcibly();throw new IOException("Cleanup timed out");}
                            if(clean.exitValue()!=0) throw new IOException("Cleanup rejected");
                        } else if(command.equals("style")) {
                            int value=j.getInt("value"); if(value<0 || value>2) throw new IllegalArgumentException("Unsupported style");
                            write("flip_button_layout",value==0?"1":"0");
                            write("no_create_gamepad_button_layout",value==2?"1":"0");
                            write("temp_abxy_layout_mode",String.valueOf(value));
                        } else if(!command.equals("ping")) {
                            Object raw=j.get("value");
                            if(!(raw instanceof Number) || ((Number)raw).doubleValue()!=((Number)raw).intValue()) throw new IllegalArgumentException("Integer required");
                            int value=((Number)raw).intValue();
                            String key=setting(command,value);
                            write(key,command.equals("led")?(value==1?"1,1":"0,0"):String.valueOf(value));
                        }
                    } catch(Exception e) { error="Thor system control failed"; }
                    byte[] response=new JSONObject().put("ok",error.isEmpty()).put("error",error).put("capture",true).put("protocol",5).toString().getBytes(StandardCharsets.UTF_8);
                    DataOutputStream out=new DataOutputStream(socket.getOutputStream());out.writeShort(response.length);out.write(response);out.flush();
                } catch(Exception ignored) { /* Invalid clients cannot terminate the helper. */ }
            }
        }
    }
}
