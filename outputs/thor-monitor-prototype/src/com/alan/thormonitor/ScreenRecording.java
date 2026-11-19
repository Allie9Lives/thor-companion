package com.alan.thormonitor;

import android.media.*;
import android.net.LocalSocket;
import android.os.SystemClock;
import android.system.Os;
import java.io.*;
import java.nio.ByteBuffer;
import java.lang.reflect.*;
import java.security.SecureRandom;
import java.util.*;
import java.util.concurrent.*;
import org.json.*;

/** Shell-owned, private temporary MP4s. The only export is an authenticated descriptor handoff. */
final class ScreenRecording {
    static final int MAX_SECONDS=600;
    /** screenrecord stops at 180 s on Android 13, so longer clips are chained segments joined on stop. */
    static final int SEGMENT_SECONDS=180,OVERLAP_SECONDS=3;
    static final long MAX_BYTES=2048L*1024*1024;
    private static File directory;
    private static Session current;
    private static final ScheduledExecutorService timer=Executors.newSingleThreadScheduledExecutor(r->{Thread t=new Thread(r,"ThorRecording");t.setDaemon(true);return t;});
    private static final class Track {int screen,pid,width,height;long offset;File file;Process process;JSONObject metadata;String[] geometry;List<File> parts=new ArrayList<>();List<Long> starts=new ArrayList<>();List<Process> processes=new ArrayList<>();ScheduledFuture<?> next;boolean joined;}
    private static final class Session {String token,error="";int mode,quality,fps;long began,epoch,expires;List<Track> tracks=new ArrayList<>();ScheduledFuture<?> limit,cleanup,watch;PlaybackRecording audio;File audioFile;boolean audioDone;String audioWarning="";}
    static synchronized void prepare(int owner)throws Exception{
        directory=new File("/data/local/tmp/thor-recordings-"+owner);
        if(!directory.exists()&&!directory.mkdir())throw new IOException("Recording storage unavailable");
        if(!directory.getCanonicalPath().equals(directory.getAbsolutePath()))throw new SecurityException();Os.chmod(directory.getPath(),0700);
        // Only our private, fixed-format files are removed after a helper restart.
        File[] processes=new File("/proc").listFiles();if(processes!=null)for(File process:processes)if(process.getName().matches("[0-9]+"))try{
            byte[] bytes=new byte[2048];int n;try(FileInputStream in=new FileInputStream(new File(process,"cmdline"))){n=in.read(bytes);}String args=n<0?"":new String(bytes,0,n,"UTF-8");
            if(args.startsWith("/system/bin/screenrecord\u0000")&&args.contains(directory.getPath()+"/"))android.os.Process.sendSignal(Integer.parseInt(process.getName()),2);
        }catch(Exception ignored){}
        File[] old=directory.listFiles();if(old!=null)for(File f:old)if(f.getName().matches("[a-f0-9]{24}-(?:[01](?:-[0-9]+)?\\.mp4(?:\\.mux)?|audio\\.m4a)"))f.delete();
    }
    private static int pid(Process p)throws Exception{
        try{return ((Number)p.getClass().getMethod("pid").invoke(p)).intValue();}catch(Exception ignored){}
        Class<?> type=p.getClass();while(type!=null){try{Field f=type.getDeclaredField("pid");f.setAccessible(true);return f.getInt(p);}catch(NoSuchFieldException e){type=type.getSuperclass();}}
        throw new IOException("Recorder process unavailable");
    }
    /** Logical display info for the top (0) or bottom (1) screen; read reflectively because the helper has no Context. */
    private static Object display(int screen,int[] logicalId)throws Exception{
        Class<?> cls=Class.forName("android.hardware.display.DisplayManagerGlobal");Object global=cls.getMethod("getInstance").invoke(null);Method info=cls.getMethod("getDisplayInfo",int.class);int id=0;
        if(screen==1){id=-1;for(int n:(int[])cls.getMethod("getDisplayIds").invoke(global)){Object d=info.invoke(global,n);if(n!=0&&d!=null&&d.getClass().getField("type").getInt(d)==1){id=n;break;}}}
        if(id<0)throw new IOException("Bottom screen unavailable");logicalId[0]=id;return info.invoke(global,id);
    }
    /** {logical display id, logical width, logical height} for input mapping. */
    static int[] logical(int screen)throws Exception{int[] id=new int[1];Object d=display(screen,id);return new int[]{id[0],d.getClass().getField("logicalWidth").getInt(d),d.getClass().getField("logicalHeight").getInt(d)};}
    static String[] geometry(int screen,int quality)throws Exception{
        Object d=display(screen,new int[1]),address=d.getClass().getField("address").get(d);long physical=(Long)address.getClass().getMethod("getPhysicalDisplayId").invoke(address);
        int width=d.getClass().getField("logicalWidth").getInt(d),height=d.getClass().getField("logicalHeight").getInt(d);int a=width,b=height;while(b!=0){int n=a%b;a=b;b=n;}int rw=width/a,rh=height/a,k=(int)Math.min((quality==1?1920.0:1280.0)/rw,(quality==1?1080.0:720.0)/rh);if((rw%2!=0||rh%2!=0)&&k%2!=0)k--;if(k<2)throw new IOException("Unsupported screen dimensions");
        return new String[]{Long.toUnsignedString(physical),(rw*k)+"x"+(rh*k)};
    }
    static synchronized JSONObject start(int mode)throws Exception{return start(mode,1,60);}
    static synchronized JSONObject start(int mode,int quality,int fps)throws Exception{
        if((quality!=0&&quality!=1)||(fps!=30&&fps!=60))throw new IllegalArgumentException("Choose a supported recording quality and frame rate");
        if(mode<0||mode>2)throw new IllegalArgumentException("Choose Top, Bottom or Both");if(current!=null)throw new IllegalStateException("Save or discard the existing recording first");
        if(directory==null||directory.getUsableSpace()<(quality==1?512L:224L)*1024*1024*(mode==2?3:2)+32L*1024*1024)throw new IOException("Free more internal storage on the device before recording");
        Session s=new Session();byte[] nonce=new byte[12];new SecureRandom().nextBytes(nonce);StringBuilder token=new StringBuilder();for(byte b:nonce)token.append(String.format(Locale.ROOT,"%02x",b&255));s.token=token.toString();s.mode=mode;s.quality=quality;s.fps=fps;s.began=SystemClock.elapsedRealtime();s.epoch=System.currentTimeMillis();s.expires=s.epoch+30*60*1000L;current=s;
        try{
            s.audioFile=new File(directory,s.token+"-audio.m4a");s.audio=new PlaybackRecording(s.audioFile);
            for(int screen:mode==2?new int[]{0,1}:new int[]{mode}){
                Track t=new Track();t.geometry=geometry(screen,quality);t.screen=screen;t.file=new File(directory,s.token+"-"+screen+".mp4");t.offset=SystemClock.elapsedRealtime()-s.began;String[] dimensions=t.geometry[1].split("x");t.width=Integer.parseInt(dimensions[0]);t.height=Integer.parseInt(dimensions[1]);
                s.tracks.add(t);segment(s,t);
            }
            s.limit=timer.schedule(()->{synchronized(ScreenRecording.class){if(current==s)stopInternal(s);}},MAX_SECONDS+1,TimeUnit.SECONDS);
            s.watch=timer.scheduleAtFixedRate(()->{synchronized(ScreenRecording.class){if(current==s){long total=0;for(Track t:s.tracks)total+=bytes(t);
                if(total>MAX_BYTES*s.tracks.size()){s.error="Recording reached its size limit";stopInternal(s);}
                // Keep room to join the segments when recording stops.
                else if(directory.getUsableSpace()<total+64L*1024*1024){s.error="Device storage is almost full. Recording stopped early.";stopInternal(s);}}}},2,2,TimeUnit.SECONDS);
            s.cleanup=timer.schedule(()->{synchronized(ScreenRecording.class){if(current==s)clearInternal(s);}},30,TimeUnit.MINUTES);
            return status(s.token);
        }catch(Exception e){clearInternal(s);throw e;}
    }
    private static long bytes(Track t){long n=0;for(File f:t.parts)n+=f.length();return n;}
    /** Starts the next segment a few seconds before the last one ends; the join cuts the overlap. */
    private static void segment(Session s,Track t)throws Exception{
        long at=SystemClock.elapsedRealtime()-s.began;int left=(int)Math.min(SEGMENT_SECONDS,MAX_SECONDS+1-at/1000);if(left<=OVERLAP_SECONDS)return;
        File file=new File(directory,s.token+"-"+t.screen+"-"+t.parts.size()+".mp4");
        Process p=new ProcessBuilder("/system/bin/screenrecord","--display-id",t.geometry[0],"--size",t.geometry[1],"--bit-rate",s.quality==1?"20000000":"8000000","--time-limit",String.valueOf(left),file.getPath()).redirectOutput(new File("/dev/null")).redirectError(new File("/dev/null")).start();
        t.parts.add(file);t.starts.add(at);t.processes.add(p);t.process=p;t.pid=pid(p);
        if(left==SEGMENT_SECONDS)t.next=timer.schedule(()->{synchronized(ScreenRecording.class){if(current==s&&t.process==p&&p.isAlive())try{segment(s,t);}catch(Exception e){s.error="Recording could not continue past "+SEGMENT_SECONDS/60+" minutes";}}},SEGMENT_SECONDS-OVERLAP_SECONDS,TimeUnit.SECONDS);
    }
    /** Concatenates segment video onto one timeline by wall-clock start, dropping each overlap. */
    private static void join(Track t)throws Exception{
        if(t.parts.size()==1){if(!t.parts.get(0).renameTo(t.file))throw new IOException("Could not keep recording");return;}
        File temporary=new File(t.file.getPath()+".mux");MediaMuxer mux=null;boolean started=false;int track=-1;long last=-1;
        ByteBuffer bytes=ByteBuffer.allocateDirect(4*1024*1024);MediaCodec.BufferInfo info=new MediaCodec.BufferInfo();
        try{
            for(int k=0;k<t.parts.size();k++){
                if(t.parts.get(k).length()<128)continue;
                long base=(t.starts.get(k)-t.starts.get(0))*1000,end=k+1<t.parts.size()&&t.parts.get(k+1).length()>=128?(t.starts.get(k+1)-t.starts.get(0))*1000:Long.MAX_VALUE;
                MediaExtractor x=new MediaExtractor();
                try(FileInputStream in=new FileInputStream(t.parts.get(k))){
                    x.setDataSource(in.getFD());int vi=-1;for(int i=0;i<x.getTrackCount();i++)if(x.getTrackFormat(i).getString(MediaFormat.KEY_MIME).startsWith("video/")){vi=i;break;}
                    if(vi<0)throw new IOException("Missing video track");x.selectTrack(vi);
                    if(mux==null){mux=new MediaMuxer(temporary.getPath(),MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);track=mux.addTrack(x.getTrackFormat(vi));mux.start();started=true;}
                    do{long time=x.getSampleTime();if(time<0||base+time>=end)break;if(base+time<=last)continue;
                        bytes.clear();int n=x.readSampleData(bytes,0);if(n<0)break;
                        info.set(0,n,base+time,x.getSampleFlags()&MediaCodec.BUFFER_FLAG_KEY_FRAME);mux.writeSampleData(track,bytes,info);last=base+time;
                    }while(x.advance());
                }finally{x.release();}
            }
            if(mux==null)throw new IOException("Empty recording");
            mux.stop();started=false;mux.release();mux=null;if(!temporary.renameTo(t.file))throw new IOException("Could not join recording");
        }finally{if(mux!=null){try{if(started)mux.stop();}catch(Exception ignored){}mux.release();}temporary.delete();}
        for(File f:t.parts)f.delete();
    }
    private static Session session(String token){if(current==null||!current.token.equals(token))throw new IllegalStateException("Recording expired or was removed");return current;}
    private static void stopInternal(Session s){
        for(Track t:s.tracks){if(t.next!=null)t.next.cancel(false);for(Process p:t.processes)if(p.isAlive()){int id=-1;try{id=pid(p);}catch(Exception ignored){}if(id>1)android.os.Process.sendSignal(id,2);else p.destroy();}}
        for(Track t:s.tracks)for(Process p:t.processes)try{if(!p.waitFor(4,TimeUnit.SECONDS)){p.destroyForcibly();s.error="Recorder did not finish cleanly";}}catch(Exception e){p.destroyForcibly();s.error="Recorder was interrupted";}
        for(Track t:s.tracks)if(!t.joined&&!t.parts.isEmpty())try{t.joined=true;join(t);}catch(Exception e){System.err.println("Recording join: "+e.getClass().getSimpleName());if(s.error.isEmpty())s.error="Recording segments could not be joined. Discard it and try again.";}
        if(s.audio!=null&&!s.audioDone){s.audioDone=true;try{s.audio.stop();for(Track t:s.tracks)PlaybackRecording.attach(t.file,s.audioFile,Math.max(0,s.began+t.offset-s.audio.began),duration(t.file));}catch(Exception e){System.err.println("Recording audio: "+e.getClass().getSimpleName());s.audioWarning="Game audio could not be saved for this clip.";}finally{s.audioFile.delete();}}
        if(s.limit!=null)s.limit.cancel(false);if(s.watch!=null)s.watch.cancel(false);
    }
    static synchronized JSONObject stop(String token)throws Exception{Session s=session(token);stopInternal(s);return status(token);}
    static synchronized JSONObject status(String token)throws Exception{
        if(current==null)return new JSONObject().put("state","idle");Session s=token.isEmpty()?current:session(token);boolean active=false,all=true;
        for(Track t:s.tracks){boolean alive=t.process.isAlive();active|=alive;all&=alive;}
        if(active&&!all){if(SystemClock.elapsedRealtime()-s.began<(MAX_SECONDS-2)*1000L)s.error="One screen stopped recording";stopInternal(s);active=false;}
        if(!active&&!s.audioDone)stopInternal(s);
        JSONArray tracks=new JSONArray();
        for(Track t:s.tracks){
            JSONObject j=new JSONObject().put("screen",t.screen).put("offset_ms",t.offset).put("bytes",t.file.length());
            if(!active){
                if(t.metadata==null){t.metadata=new JSONObject();try{long ms=duration(t.file);if(ms<=0||ms>(MAX_SECONDS+10)*1000L||t.file.length()<128||t.file.length()>MAX_BYTES)throw new IOException("Invalid MP4 duration");t.metadata.put("duration_ms",ms).put("width",t.width).put("height",t.height);Os.chmod(t.file.getPath(),0600);}catch(Exception e){System.err.println("Recording finalize: bytes="+t.file.length()+", exit="+t.process.exitValue()+", "+e.toString().replaceAll("[a-f0-9]{24}","[clip]"));s.error="Recording could not be finalized. Discard it and try again.";}}
                for(Iterator<String> keys=t.metadata.keys();keys.hasNext();){String key=keys.next();j.put(key,t.metadata.get(key));}
            }
            tracks.put(j);
        }
        return new JSONObject().put("token",s.token).put("mode",s.mode).put("quality",s.quality).put("fps",s.fps).put("state",active?"recording":s.error.isEmpty()?"ready":"failed").put("elapsed_ms",Math.min(MAX_SECONDS*1000L,SystemClock.elapsedRealtime()-s.began)).put("max_seconds",MAX_SECONDS).put("expires_at",s.expires).put("tracks",tracks).put("error",s.error).put("audio",s.audioDone&&s.audioWarning.isEmpty()).put("audio_warning",s.audioWarning);
    }
    // Read the finalized MP4 movie header directly: shell helpers have no app Context
    // for MediaMetadataRetriever's media service attribution.
    private static long duration(File file)throws IOException{
        try(RandomAccessFile in=new RandomAccessFile(file,"r")){return movieHeader(in,0,in.length(),0);}
    }
    private static long movieHeader(RandomAccessFile in,long begin,long end,int depth)throws IOException{
        if(depth>1)throw new IOException("Invalid MP4 nesting");
        for(long at=begin;at+8<=end;){in.seek(at);long size=Integer.toUnsignedLong(in.readInt());int type=in.readInt();long header=8;if(size==1){size=in.readLong();header=16;}else if(size==0)size=end-at;if(size<header||size>end-at)throw new IOException("Invalid MP4 box");
            if(type==0x6d6f6f76)return movieHeader(in,at+header,at+size,depth+1);
            if(type==0x6d766864){int version=in.readUnsignedByte();in.skipBytes(3);if(version!=0&&version!=1)throw new IOException("Invalid movie version");in.skipBytes(version==1?16:8);long scale=Integer.toUnsignedLong(in.readInt());long ticks=version==1?in.readLong():Integer.toUnsignedLong(in.readInt());if(scale==0||ticks<=0||ticks>(MAX_SECONDS+10)*scale)throw new IOException("Invalid movie duration");return ticks*1000/scale;}
            at+=size;
        }throw new IOException("Missing finalized movie header");
    }
    static synchronized void sendFile(String token,int screen,LocalSocket socket,DataOutputStream out)throws Exception{
        Session s=session(token);if(!status(token).optString("state").equals("ready"))throw new IllegalStateException("Stop recording before saving");
        Track found=null;for(Track t:s.tracks)if(t.screen==screen)found=t;if(found==null)throw new IllegalArgumentException("Unknown recording screen");
        try(FileInputStream file=new FileInputStream(found.file)){
            socket.setFileDescriptorsForSend(new FileDescriptor[]{file.getFD()});out.writeByte(1);out.flush();socket.setFileDescriptorsForSend(null);out.writeLong(found.file.length());out.flush();
        }
    }
    private static void clearInternal(Session s){stopInternal(s);for(Track t:s.tracks){t.file.delete();for(File f:t.parts)f.delete();}if(s.audioFile!=null)s.audioFile.delete();if(s.cleanup!=null)s.cleanup.cancel(false);if(current==s)current=null;}
    static synchronized JSONObject clear(String token)throws Exception{clearInternal(session(token));return new JSONObject().put("state","idle");}
}
