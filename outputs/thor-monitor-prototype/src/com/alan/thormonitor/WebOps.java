package com.alan.thormonitor;

import android.content.*;import android.os.SystemClock;
import java.io.*;import java.net.*;import java.nio.charset.StandardCharsets;import java.util.*;import java.util.concurrent.*;import javax.net.ssl.*;import org.json.*;

/** Independent HTTPS browser endpoint. Never uses companion pairing credentials. */
final class WebOps {
 static final int PORT=47184;
 private static final java.util.concurrent.atomic.AtomicBoolean captureBusy=new java.util.concurrent.atomic.AtomicBoolean();
 private static final Semaphore transferSlot=new Semaphore(2);
 static final WebSessions sessions=new WebSessions();
 private static final List<SSLServerSocket> listeners=new ArrayList<>();
 private static final Set<Socket> sockets=ConcurrentHashMap.newKeySet();
 private static final ThreadPoolExecutor workers=new ThreadPoolExecutor(4,4,30,TimeUnit.SECONDS,new ArrayBlockingQueue<Runnable>(12));
 private static List<String> bound=Collections.emptyList();private static long issued;static volatile String error="";
 static SharedPreferences prefs(Context c){return c.getSharedPreferences("web_ops",0);}
 static boolean configured(Context c){return prefs(c).contains("hash");}
 static boolean enabled(Context c){return prefs(c).getBoolean("enabled",false)&&configured(c);}
 static void configure(Context c,String user,char[] password)throws Exception{
  try{WebSessions.validate(user,password);byte[] salt=WebSessions.salt(),hash=WebSessions.derive(password,salt);
   synchronized(sessions){if(!prefs(c).edit().putString("revision",WebSessions.token()).putString("user",user).putString("salt",Base64.getEncoder().encodeToString(salt)).putString("hash",Base64.getEncoder().encodeToString(hash)).commit())throw new IOException("Could not save login");
   Arrays.fill(hash,(byte)0);revoke();}
  }finally{Arrays.fill(password,'\0');}
 }
 static void revoke(){sessions.clear();MonitorService.restChanged();}
 static boolean awake(Context c){return !c.getSharedPreferences("monitor",0).getBoolean("rest_manual",false)&&sessions.awake(SystemClock.elapsedRealtime());}
 static synchronized boolean running(){return !listeners.isEmpty();}
 static String host(String ip){return (ip.contains(":")?"["+ip+"]":ip)+":"+PORT;}
 static boolean matchesHost(String ip,String authority){
  if(!ip.contains(":"))return host(ip).equals(authority);
  if(!authority.matches("\\[[0-9a-fA-F:.]{2,64}\\]:"+PORT))return false;
  try{return Arrays.equals(InetAddress.getByName(ip).getAddress(),InetAddress.getByName(authority.substring(1,authority.indexOf(']'))).getAddress());}catch(Exception e){return false;}
 }
 static synchronized List<String> urlList(){ArrayList<String> result=new ArrayList<>();for(String ip:bound)try{if(!InetAddress.getByName(ip).isLoopbackAddress())result.add("https://"+host(ip));}catch(Exception ignored){}return result;}
 static synchronized String urls(){return String.join("\n",urlList());}
 static synchronized String summaryUrls(){StringBuilder text=new StringBuilder();int n=0;for(String ip:bound)if(!ip.contains(":")&&!ip.equals("127.0.0.1")&&n++<2){if(text.length()>0)text.append('\n');text.append("https://").append(host(ip));}return text.length()>0?text.toString():urls();}
 static synchronized void stop(){for(ServerSocket s:listeners)try{s.close();}catch(Exception ignored){}listeners.clear();bound=Collections.emptyList();for(Socket s:sockets)try{s.close();}catch(Exception ignored){}revoke();}
 static synchronized void refresh(Context context){
  Context c=context.getApplicationContext();sessions.idleMinutes(prefs(c).getInt("idle_minutes",30));if(!enabled(c)){if(running())stop();return;}
  try{List<String> ips=WebTls.addresses();if(ips.equals(bound)&&SystemClock.elapsedRealtime()-issued<7*86400000L)return;
   // Prepare TLS before replacing listeners. Sessions survive IP changes only on the same origin.
   SSLContext tls=WebTls.context(c,ips);for(ServerSocket s:listeners)try{s.close();}catch(Exception ignored){}listeners.clear();bound=new ArrayList<>();
   for(String ip:ips){SSLServerSocket listener=(SSLServerSocket)tls.getServerSocketFactory().createServerSocket();listener.setReuseAddress(true);listener.setEnabledProtocols(new String[]{"TLSv1.2","TLSv1.3"});
    try{listener.bind(new InetSocketAddress(InetAddress.getByName(ip),PORT),8);}catch(IOException e){listener.close();continue;}
    listeners.add(listener);bound.add(ip);Thread accept=new Thread(()->accept(c,listener,ip),"web-ops-listener");accept.setDaemon(true);accept.start();
   }issued=SystemClock.elapsedRealtime();error=listeners.isEmpty()?"No private network address available":"";
  }catch(Exception e){error="Could not start HTTPS ("+e.getClass().getSimpleName()+")";}
 }
 private static void accept(Context c,SSLServerSocket listener,String ip){
  while(!listener.isClosed())try{Socket s=listener.accept();s.setSoTimeout(10000);if(!WebTls.privateAddress(s.getInetAddress())){s.close();continue;}sockets.add(s);
   try{workers.execute(()->serve(c,s,ip));}catch(RejectedExecutionException e){sockets.remove(s);s.close();}
  }catch(IOException e){break;}
 }
 private static void json(OutputStream out,int status,JSONObject value,String extra)throws Exception{WebHttp.bytes(out,status,"application/json; charset=utf-8",value.toString().getBytes(StandardCharsets.UTF_8),extra);}
 private static void fail(OutputStream out,int status,String message)throws Exception{json(out,status,new JSONObject().put("error",message),null);}
 private static final class WebOutput extends FilterOutputStream {boolean started;WebOutput(OutputStream o){super(o);}public void write(int b)throws IOException{started=true;out.write(b);}public void write(byte[] b,int p,int n)throws IOException{started=true;out.write(b,p,n);}}
 private static void sendDownload(WebHttp.Request r,OutputStream out,InputStream stream,long size,long modified,String attachment,WebFiles.Guard guard)throws Exception{
  String etag="\""+Long.toHexString(size)+"-"+Long.toHexString(modified)+"\"",rangeHeader=r.header("range");if(!r.header("if-range").isEmpty()&&!r.header("if-range").equals(etag))rangeHeader="";
  WebRange range;try{range=WebRange.parse(rangeHeader,size);}catch(IllegalArgumentException e){WebHttp.bytes(out,416,"application/octet-stream",new byte[0],"Content-Range: bytes */"+size+"\r\n");return;}
  guard.check();WebRange.seek(stream,range.start);WebHttp.head(out,range.partial?206:200,attachment.contains(".mp4")?"video/mp4":"application/octet-stream",range.length(),attachment+range.headers()+"ETag: "+etag+"\r\n");
  if(!r.method.equals("HEAD"))WebFiles.copy(stream,out,range.length(),guard);out.flush();
 }
 private static void serve(Context c,Socket socket,String ip){
  try(Socket s=socket){((SSLSocket)s).startHandshake();InputStream in=new BufferedInputStream(s.getInputStream());WebOutput out=new WebOutput(s.getOutputStream());try{WebHttp.Request r;
   if(!enabled(c)){fail(out,503,"Web Ops is stopped");return;}
   try{r=WebHttp.read(in);}catch(Exception e){fail(out,400,"Invalid request");return;}
   String origin="https://"+r.host;
   if(!matchesHost(ip,r.host)){fail(out,421,"Use the address shown on the Thor");return;}
   if(!r.header("origin").isEmpty()&&!r.header("origin").equals(origin)){fail(out,403,"Origin rejected");return;}
   if(!r.method.equals("GET")&&!r.method.equals("HEAD")&&!r.header("origin").equals(origin)){fail(out,403,"Origin required");return;}
   if(r.method.equals("GET")&&r.path.equals("/appearance.json")){json(out,200,new JSONObject().put("theme",HostTheme.name(c)),null);return;}
   if(r.method.equals("GET")&&Arrays.asList("/","/theme.js","/app.js","/app.css","/extras.mjs","/mobile-ui.mjs","/downloads.mjs","/notification-policy.mjs","/video-export.mjs","/sw.js","/manifest.webmanifest","/app-icon.png","/favicon.png","/favicon.ico","/touch-icon.png","/icon-192.png","/icon-512.png","/vendor/mediabunny.mjs","/vendor/MEDIABUNNY-LICENSE.txt","/vendor/mediabunny-source.tgz","/notices.txt").contains(r.path)){
    String asset=r.path.equals("/")?"index.html":r.path.substring(1);byte[] data;try(InputStream file=c.getAssets().open("web-ops/"+asset)){ByteArrayOutputStream b=new ByteArrayOutputStream();byte[] part=new byte[8192];for(int n;(n=file.read(part))!=-1;)b.write(part,0,n);data=b.toByteArray();}
    if(asset.equals("index.html"))data=new String(data,StandardCharsets.UTF_8).replace("__THOR_THEME__",HostTheme.name(c)).getBytes(StandardCharsets.UTF_8);
    WebHttp.bytes(out,200,asset.endsWith("js")?"text/javascript; charset=utf-8":asset.endsWith("css")?"text/css; charset=utf-8":asset.endsWith("png")?"image/png":asset.endsWith("ico")?"image/x-icon":asset.endsWith("tgz")?"application/gzip":asset.endsWith("webmanifest")?"application/manifest+json":asset.endsWith("txt")?"text/plain; charset=utf-8":"text/html; charset=utf-8",data,asset.equals("sw.js")?"Service-Worker-Allowed: /\r\n":null);return;
   }
   long now=SystemClock.elapsedRealtime();
   if(r.path.equals("/api/login")&&r.method.equals("POST")){
    if(!sessions.allowLogin(s.getInetAddress().getHostAddress(),now)){fail(out,429,"Too many attempts. Try again in five minutes.");return;}
    JSONObject body=new JSONObject(new String(r.body(in,4096),StandardCharsets.UTF_8));String user=body.optString("username");char[] password=body.optString("password").toCharArray();boolean ok=false;String revision=prefs(c).getString("revision","");
    try{if(password.length<=128&&configured(c))ok=WebSessions.verify(user,password,prefs(c).getString("user",""),Base64.getDecoder().decode(prefs(c).getString("salt","")),Base64.getDecoder().decode(prefs(c).getString("hash","")));}finally{Arrays.fill(password,'\0');}
    if(!ok){fail(out,401,"Incorrect username or password");return;}
    WebSessions.Session session;synchronized(sessions){if(!enabled(c)||!revision.equals(prefs(c).getString("revision",""))){fail(out,401,"Login changed. Try again.");return;}session=sessions.create(origin,SystemClock.elapsedRealtime());}if(session==null){fail(out,429,"End another browser session on the Thor first");return;}
    session.label=WebSessions.clientLabel(r.header("user-agent"));MonitorService.restChanged();json(out,200,new JSONObject().put("csrf",session.csrf),"Set-Cookie: __Host-thor_web="+session.cookie+"; Path=/; Secure; HttpOnly; SameSite=Strict\r\n");return;
   }
   WebSessions.Session session=sessions.get(WebHttp.cookie(r),origin,now);if(session==null){fail(out,401,"Sign in to Web Ops");return;}
   if(!r.method.equals("GET")&&!r.method.equals("HEAD")&&!sessions.touch(session,r.header("x-thor-csrf"),now)){fail(out,403,"Session expired. Sign in again.");return;}
   if(r.method.equals("POST"))MonitorService.restChanged();
   if(r.path.equals("/api/session")&&r.method.equals("GET")){json(out,200,new JSONObject().put("csrf",session.csrf).put("username",prefs(c).getString("user","")),null);return;}
   if(r.path.equals("/api/logout")&&r.method.equals("POST")){sessions.remove(session);MonitorService.restChanged();json(out,200,new JSONObject().put("ok",true),"Set-Cookie: __Host-thor_web=; Path=/; Secure; HttpOnly; SameSite=Strict; Max-Age=0\r\n");return;}
   if(r.path.equals("/api/interaction")&&r.method.equals("POST")){json(out,200,new JSONObject().put("ok",true),null);return;}
   if(r.path.equals("/api/wifi")&&r.method.equals("GET")){json(out,200,PowerSaving.network(c),null);return;}
   if(r.path.equals("/api/settings")&&r.method.equals("GET")){json(out,200,WebSettings.read(c),null);return;}
   if(r.path.equals("/api/settings")&&r.method.equals("POST")){json(out,200,WebSettings.save(c,new JSONObject(new String(r.body(in,4096),StandardCharsets.UTF_8))),null);return;}
   if(r.path.equals("/api/sessions")&&r.method.equals("GET")){JSONArray rows=new JSONArray();for(WebSessions.Session peer:sessions.list(now))rows.put(new JSONObject().put("id",peer.id).put("label",peer.label).put("current",peer==session).put("age_minutes",Math.max(0,(now-peer.created)/60000)).put("idle_minutes",Math.max(0,(now-peer.interacted)/60000)));json(out,200,new JSONObject().put("sessions",rows),null);return;}
   if(r.path.equals("/api/sessions/revoke")&&r.method.equals("POST")){JSONObject body=new JSONObject(new String(r.body(in,256),StandardCharsets.UTF_8));String id=body.getString("id");if(!id.matches("[A-Za-z0-9_-]{43}"))throw new IllegalArgumentException("Invalid session");sessions.revoke(id);MonitorService.restChanged();json(out,200,new JSONObject().put("ok",true).put("current",session.id.equals(id)),null);return;}
   if(r.path.equals("/api/qr")&&r.method.equals("GET")){int index=Integer.parseInt(r.query.getOrDefault("index","0"));List<String> urls=urlList();if(index<0||index>=urls.size())throw new IllegalArgumentException("Address unavailable");WebHttp.bytes(out,200,"image/png",WebQr.png(urls.get(index)),null);return;}
   if(r.path.equals("/api/certificate")&&r.method.equals("GET")){WebHttp.bytes(out,200,"application/x-x509-ca-cert",WebTls.root(c).getEncoded(),"Content-Disposition: attachment; filename=Thor-Web-Ops-CA.crt\r\n");return;}
   if(r.path.equals("/api/capture")&&r.method.equals("POST")){
    int mode=Integer.parseInt(r.query.getOrDefault("mode","-1"));if(mode<0||mode>2)throw new IllegalArgumentException("Choose Top, Bottom or Both");
    if(!new ThorControls(c).helperReady())throw new IllegalStateException("Set up Controls recovery on the Thor first");
    if(!captureBusy.compareAndSet(false,true)){fail(out,409,"A screenshot is already being captured");return;}
    try{WebHttp.bytes(out,200,"application/x-thor-screenshot",new ThorControls(c).captureImage(mode),null);}finally{captureBusy.set(false);}return;
   }
   if(r.path.startsWith("/api/record/")){
    String action=r.path.substring("/api/record/".length()),token=r.query.getOrDefault("token","");if(!token.isEmpty()&&!token.matches("[a-f0-9]{24}"))throw new IllegalArgumentException("Invalid recording");
    if(action.equals("file")&&(r.method.equals("GET")||r.method.equals("HEAD"))){if(!transferSlot.tryAcquire()){fail(out,409,"Another transfer is running");return;}try{int screen=Integer.parseInt(r.query.getOrDefault("screen","-1"));if(screen<0||screen>1)throw new IllegalArgumentException("Choose a screen");
     try(RecordingBroker.Clip clip=RecordingBroker.open(c,token,screen)){sendDownload(r,out,clip.stream,clip.size,0,"Content-Disposition: attachment; filename=Thor-"+(screen==0?"top":"bottom")+".mp4\r\n",()->{if(sessions.get(session.cookie,origin,SystemClock.elapsedRealtime())!=session||!enabled(c)||c.getSharedPreferences("monitor",0).getBoolean("rest_manual",false))throw new IOException("Session ended");});}return;}finally{transferSlot.release();}
    }
    if(action.equals("status")&&r.method.equals("GET")||Arrays.asList("start","stop","clear").contains(action)&&r.method.equals("POST")){
     int mode=Integer.parseInt(r.query.getOrDefault("mode","0")),quality=Integer.parseInt(r.query.getOrDefault("quality","1")),fps=Integer.parseInt(r.query.getOrDefault("fps","60"));if(mode<0||mode>2||quality<0||quality>1||fps!=30&&fps!=60)throw new IllegalArgumentException("Invalid recording options");
     json(out,200,RecordingBroker.request(c,"record_"+action,token,mode,quality,fps),null);return;
    }throw new IllegalArgumentException("Unknown recording action");
   }
   if(r.path.startsWith("/api/files/")&&Arrays.asList("GET","HEAD","PUT").contains(r.method)){
    String root=r.query.getOrDefault("root",""),path=r.query.getOrDefault("path","");
    if(r.path.equals("/api/files/roots")&&r.method.equals("GET")){json(out,200,WebFiles.roots(c),null);return;}
    if(r.path.equals("/api/files/list")&&r.method.equals("GET")){json(out,200,WebFiles.list(c,root,path,Integer.parseInt(r.query.getOrDefault("offset","0"))),null);return;}
    if(r.path.equals("/api/files/file")){
     if(!transferSlot.tryAcquire()){fail(out,409,"Another transfer is running. Try again when it finishes.");return;}try{
     android.os.PowerManager.WakeLock hold=c.getSystemService(android.os.PowerManager.class).newWakeLock(android.os.PowerManager.PARTIAL_WAKE_LOCK,"ThorMonitor:WebTransfer");
     WebFiles.Guard guard=()->{if(sessions.get(session.cookie,origin,SystemClock.elapsedRealtime())!=session||!enabled(c)||c.getSharedPreferences("monitor",0).getBoolean("rest_manual",false))throw new IOException("Transfer cancelled");};guard.check();hold.acquire(20*60000L);
     try{if(r.method.equals("GET")||r.method.equals("HEAD")){try(WebFiles.Download file=WebFiles.open(c,root,path)){String name=path.substring(path.lastIndexOf('/')+1);String attachment="Content-Disposition: attachment; filename*=UTF-8''"+java.net.URLEncoder.encode(name,"UTF-8").replace("+","%20")+"\r\n";sendDownload(r,out,file.stream,file.length,file.modified,attachment,guard);}return;}
      if(!r.headers.containsKey("content-length"))throw new IllegalArgumentException("File size required");WebFiles.upload(c,root,path,r.query.getOrDefault("name",""),r.length,in,guard);json(out,200,new JSONObject().put("ok",true),null);return;
     }finally{if(hold.isHeld())hold.release();}
     }finally{transferSlot.release();}
    }
   }
   if(r.path.equals("/api/control")&&r.method.equals("POST")){
    byte[] command=r.body(in,180);JSONObject body=new JSONObject(new String(command,StandardCharsets.UTF_8));
    if(!Arrays.asList("find","power","brightness","volume","hz","fan","performance","focus","bypass","vibration","style","clean","led","text","key","app_open","app_close","ftp_start","ftp_stop").contains(body.optString("set")))throw new IllegalArgumentException("Unknown control");
    WebHttp.bytes(out,200,"application/json; charset=utf-8",MonitorService.networkControl(command),null);return;
   }
   if(r.path.equals("/api/controls")&&r.method.equals("GET")){WebHttp.bytes(out,200,"application/json; charset=utf-8",MonitorService.networkRead("control"),null);return;}
   if(r.path.equals("/api/files/stat")&&r.method.equals("GET")){try(WebFiles.Download file=WebFiles.open(c,r.query.getOrDefault("root",""),r.query.getOrDefault("path",""))){json(out,200,new JSONObject().put("size",file.length).put("modified",file.modified).put("etag",file.etag()),null);}return;}
   if(r.path.equals("/api/apps")&&r.method.equals("GET")){
    int cursor=Integer.parseInt(r.query.getOrDefault("cursor","0"));json(out,200,AppCatalog.webPage(c,cursor,r.query.getOrDefault("open","").equals("1")),null);return;
   }
   if(r.path.equals("/api/app-icon")&&r.method.equals("GET")){WebHttp.bytes(out,200,"image/png",AppCatalog.icon(c,r.query.getOrDefault("package",""),r.query.getOrDefault("revision","")),null);return;}
   if(r.path.equals("/api/activity")&&r.method.equals("GET")){if(MonitorService.activity==null)throw new IllegalStateException("Start monitoring first");json(out,200,MonitorService.activity.reply("web"),null);return;}
   if(r.path.equals("/api/history")&&r.method.equals("GET")){
    JSONArray rows=new JSONArray(),events=new JSONArray();long since=System.currentTimeMillis()-(r.query.getOrDefault("range","24h").equals("7d")?7L:1L)*86400000;
    for(BatterySample sample:BatteryHistory.get(c).localSamples(since))rows.put(new JSONArray().put(sample.time).put(sample.level).put(sample.plugged).put(sample.screenOn).put(sample.temperature));
    for(long[] event:BatteryHistory.get(c).sleepEvents())if(event[0]>=since)events.put(new JSONArray().put(event[0]).put(event[1]));json(out,200,new JSONObject().put("samples",rows).put("sleep",events),null);return;
   }
   if(r.path.equals("/api/ftp")&&r.method.equals("GET")){json(out,200,FtpAccess.command(c,"ftp_status","web"),null);return;}
   if(r.path.equals("/api/state")&&r.method.equals("GET")){
    json(out,200,MonitorService.webState(),null);return;
   }
   fail(out,404,"Not found");
   }catch(Exception e){if(out.started)try{Telemetry.log(c,"web_stream_failed",new JSONObject().put("error",e.getClass().getSimpleName()));}catch(Exception ignored){}if(!out.started)fail(out,e instanceof WebFiles.Conflict?409:e instanceof FileNotFoundException?404:e instanceof SecurityException?403:e instanceof IllegalArgumentException||e instanceof JSONException?400:503,e instanceof FileNotFoundException?"File or folder unavailable":e instanceof SecurityException?"This folder is protected or access was revoked.":e instanceof IllegalStateException||e instanceof IllegalArgumentException?String.valueOf(e.getMessage()):e instanceof JSONException?"Invalid request":"Thor is unavailable. Check monitoring on the device.");}
  }catch(Exception ignored){}finally{sockets.remove(socket);}
 }
}
