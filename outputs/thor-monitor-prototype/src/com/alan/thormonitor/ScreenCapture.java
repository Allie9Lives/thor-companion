package com.alan.thormonitor;

import java.io.*;
import java.lang.reflect.*;
import java.util.concurrent.*;

/** Shell-UID capture into stdout and RAM only. Never supplies a filename to screencap. */
final class ScreenCapture {
    static final int MAX_BYTES=12*1024*1024;
    static byte[] capture(int mode) throws Exception {
        if(mode<0 || mode>2)throw new IllegalArgumentException("Unknown screen");
        Class<?> cls=Class.forName("android.hardware.display.DisplayManagerGlobal");
        Object global=cls.getMethod("getInstance").invoke(null);
        Method infoMethod=cls.getMethod("getDisplayInfo",int.class);
        int bottom=-1;
        for(int id:(int[])cls.getMethod("getDisplayIds").invoke(global)) {
            Object info=infoMethod.invoke(global,id);
            if(id!=0 && info!=null && info.getClass().getField("type").getInt(info)==1){bottom=id;break;}
        }
        ByteArrayOutputStream bytes=new ByteArrayOutputStream();DataOutputStream out=new DataOutputStream(bytes);
        out.write(new byte[]{'T','H','S','1'});out.writeByte(mode==2?2:1);
        for(int screen:mode==2?new int[]{0,1}:new int[]{mode}) {
            int logical=screen==0?0:bottom;if(logical<0)throw new IOException("Bottom screen unavailable");
            Object info=infoMethod.invoke(global,logical);
            Object address=info.getClass().getField("address").get(info);
            long physical=(Long)address.getClass().getMethod("getPhysicalDisplayId").invoke(address);
            byte[] png=png(physical);
            if(bytes.size()+png.length+5>MAX_BYTES)throw new IOException("Screenshot too large");
            out.writeByte(screen);out.writeInt(png.length);out.write(png);
        }
        return bytes.toByteArray();
    }
    private static byte[] png(long display) throws Exception {
        Process process=new ProcessBuilder("/system/bin/screencap","-p","-d",Long.toUnsignedString(display))
            .redirectError(new File("/dev/null")).start();
        ExecutorService reader=Executors.newSingleThreadExecutor();
        Future<byte[]> result=reader.submit(()->{
            try(InputStream in=process.getInputStream();ByteArrayOutputStream bytes=new ByteArrayOutputStream()) {
                byte[] buf=new byte[16384];int count;
                while((count=in.read(buf))!=-1){if(bytes.size()+count>MAX_BYTES)throw new IOException("Screenshot too large");bytes.write(buf,0,count);}
                return bytes.toByteArray();
            }
        });
        try {
            if(!process.waitFor(8,TimeUnit.SECONDS))throw new IOException("Capture timed out");
            byte[] png=result.get(1,TimeUnit.SECONDS);
            if(process.exitValue()!=0 || png.length<24 || png[0]!=(byte)137 || png[1]!='P' || png[2]!='N' || png[3]!='G')
                throw new IOException("Capture unavailable");
            return png;
        }finally{process.destroyForcibly();result.cancel(true);reader.shutdownNow();}
    }
}
