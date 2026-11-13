package com.alan.thormonitor.tests;
import android.app.*;import android.os.*;import android.content.*;import java.io.*;import java.lang.reflect.*;import org.json.*;
public class RecordingDeviceTest extends Instrumentation {
 private boolean reset,keep;private android.media.MediaPlayer tone;private File toneFile;
 private void startTone(Context c)throws Exception{
  toneFile=new File(c.getCacheDir(),"recording-tone.wav");int rate=48000,samples=rate*2;try(DataOutputStream out=new DataOutputStream(new FileOutputStream(toneFile))){out.writeBytes("RIFF");little(out,36+samples*4,4);out.writeBytes("WAVEfmt ");little(out,16,4);little(out,1,2);little(out,2,2);little(out,rate,4);little(out,rate*4,4);little(out,4,2);little(out,16,2);out.writeBytes("data");little(out,samples*4,4);for(int i=0;i<samples;i++){int value=(int)(Math.sin(i*2*Math.PI*440/rate)*1200);little(out,value,2);little(out,value,2);}}
  tone=new android.media.MediaPlayer();tone.setAudioAttributes(new android.media.AudioAttributes.Builder().setUsage(android.media.AudioAttributes.USAGE_GAME).setContentType(android.media.AudioAttributes.CONTENT_TYPE_MUSIC).build());tone.setDataSource(toneFile.getPath());tone.setLooping(true);tone.setVolume(.2f,.2f);tone.prepare();tone.start();
 }
 private void little(DataOutputStream out,int n,int count)throws Exception{for(int i=0;i<count;i++)out.writeByte(n>>>(i*8));}
 private void stopTone(){if(tone!=null){tone.release();tone=null;}if(toneFile!=null)toneFile.delete();}
 private void verifyAudio(File file)throws Exception{
  android.media.MediaExtractor extractor=new android.media.MediaExtractor();android.media.MediaCodec decoder=null;try{extractor.setDataSource(file.getPath());android.media.MediaFormat format=null;for(int i=0;i<extractor.getTrackCount();i++){android.media.MediaFormat candidate=extractor.getTrackFormat(i);if(candidate.getString("mime").startsWith("audio/")){format=candidate;extractor.selectTrack(i);break;}}if(format==null)throw new AssertionError("Missing game audio track");decoder=android.media.MediaCodec.createDecoderByType(format.getString("mime"));decoder.configure(format,null,null,0);decoder.start();android.media.MediaCodec.BufferInfo info=new android.media.MediaCodec.BufferInfo();int peak=0;for(int tries=0;tries<120&&peak<20;tries++){int slot=decoder.dequeueInputBuffer(10000);if(slot>=0){java.nio.ByteBuffer buffer=decoder.getInputBuffer(slot);int size=extractor.readSampleData(buffer,0);decoder.queueInputBuffer(slot,0,Math.max(0,size),Math.max(0,extractor.getSampleTime()),size<0?4:0);if(size>=0)extractor.advance();}int ready=decoder.dequeueOutputBuffer(info,10000);if(ready>=0){java.nio.ByteBuffer decoded=decoder.getOutputBuffer(ready).order(java.nio.ByteOrder.LITTLE_ENDIAN);for(int at=info.offset;at+1<info.offset+info.size;at+=2)peak=Math.max(peak,Math.abs((int)decoded.getShort(at)));decoder.releaseOutputBuffer(ready,false);if((info.flags&4)!=0)break;}}if(peak<20)throw new AssertionError("Game audio is silent");}finally{extractor.release();if(decoder!=null){decoder.stop();decoder.release();}}
 }

 public void onCreate(Bundle b){super.onCreate(b);reset="true".equals(b.getString("reset"));keep="true".equals(b.getString("keep"));start();}
 public void onStart(){Bundle result=new Bundle();Context c=getTargetContext();Method request=null;String token="";try{
  c.startForegroundService(new Intent().setClassName(c,"com.alan.thormonitor.MonitorService"));Thread.sleep(1000);
  Class<?> broker=c.getClassLoader().loadClass("com.alan.thormonitor.RecordingBroker");request=broker.getDeclaredMethod("request",Context.class,String.class,String.class,int.class);request.setAccessible(true);Method open=broker.getDeclaredMethod("open",Context.class,String.class,int.class);open.setAccessible(true);
  JSONObject prior=(JSONObject)request.invoke(null,c,"record_status","",0);if(!prior.optString("state").equals("idle")){if(!reset)throw new IllegalStateException("Existing clip retained; pass reset only for a known test capture");request.invoke(null,c,"record_clear",prior.getString("token"),0);}
  startTone(c);int verified=0;
  for(int mode:new int[]{0,1,2}){
   JSONObject started=(JSONObject)request.invoke(null,c,"record_start","",mode);token=started.getString("token");Thread.sleep(mode==2?3500:2200);
   JSONObject stopped=(JSONObject)request.invoke(null,c,"record_stop",token,0);if(!stopped.optString("state").equals("ready"))throw new AssertionError(stopped.optString("error"));
   if(!stopped.optBoolean("audio"))throw new AssertionError(stopped.optString("audio_warning","Audio missing"));
   if(stopped.optInt("quality")!=1||stopped.optInt("fps")!=60)throw new AssertionError("Recording settings were lost");
   JSONArray tracks=stopped.getJSONArray("tracks");if(tracks.length()!=(mode==2?2:1))throw new AssertionError("Wrong recording track count");
   for(int n=0;n<tracks.length();n++){
    JSONObject track=tracks.getJSONObject(n);if(track.getLong("duration_ms")<500)throw new AssertionError("Clip too short");
    Object clip=open.invoke(null,c,token,track.getInt("screen"));Field stream=clip.getClass().getDeclaredField("stream"),size=clip.getClass().getDeclaredField("size");stream.setAccessible(true);size.setAccessible(true);
    File downloaded=new File(c.getCacheDir(),"recording-verify.mp4");try(InputStream file=(InputStream)stream.get(clip);OutputStream copy=new FileOutputStream(downloaded)){
     byte[] header=new byte[12];if(file.read(header)!=12||header[4]!='f'||header[5]!='t'||header[6]!='y'||header[7]!='p')throw new AssertionError("Invalid MP4 handoff");
     // Descriptor transfer must not monopolize the helper while the file stays open.
     Class<?> controls=c.getClassLoader().loadClass("com.alan.thormonitor.ThorControls");Method status=controls.getDeclaredMethod("helperStatus",Context.class);status.setAccessible(true);JSONObject helper=(JSONObject)status.invoke(null,c);if(helper.optInt("protocol")<7)throw new AssertionError("Controls blocked by recording transfer");
     copy.write(header);long received=header.length;byte[] b=new byte[65536];int count;while((count=file.read(b))!=-1){received+=count;copy.write(b,0,count);}if(received!=size.getLong(clip))throw new AssertionError("Truncated recording descriptor");
    }if(keep&&mode==2)java.nio.file.Files.copy(downloaded.toPath(),new File(c.getCacheDir(),track.getInt("screen")==0?"recording-top-high.mp4":"recording-bottom-high.mp4").toPath(),java.nio.file.StandardCopyOption.REPLACE_EXISTING);try{verifyAudio(downloaded);}finally{downloaded.delete();}verified++;
   }
   request.invoke(null,c,"record_clear",token,0);token="";
   if(!((JSONObject)request.invoke(null,c,"record_status","",0)).optString("state").equals("idle"))throw new AssertionError("Recording files not cleared");
  }
  try{request.invoke(null,c,"record_status","../../escape",0);throw new AssertionError("Malformed recording token accepted");}catch(InvocationTargetException expected){}
  stopTone();result.putInt("verified_tracks",verified);result.putString("status","passed: top, bottom and simultaneous MP4 capture; stop/finalize, private FD download, parallel controls, invalid-token denial and cleanup");finish(0,result);
 }catch(Throwable e){stopTone();if(request!=null&&!token.isEmpty())try{request.invoke(null,c,"record_clear",token,0);}catch(Exception ignored){}result.putString("error",e.toString()+(e.getCause()==null?"":" cause="+e.getCause()));finish(1,result);}finally{if(request!=null&&!token.isEmpty())try{request.invoke(null,c,"record_clear",token,0);}catch(Exception ignored){}}}
}
