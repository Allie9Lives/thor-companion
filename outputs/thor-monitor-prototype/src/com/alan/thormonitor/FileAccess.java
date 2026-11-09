package com.alan.thormonitor;

import android.content.*;
import android.database.Cursor;
import android.net.Uri;
import android.provider.DocumentsContract;
import org.json.*;
import java.io.*;
import java.net.*;
import java.security.*;
import java.security.cert.X509Certificate;
import java.util.*;
import java.util.concurrent.*;
import javax.net.ssl.*;
import android.security.keystore.*;
import javax.security.auth.x500.X500Principal;

/** Explicitly shared SAF trees, pinned TLS and a revocable owner credential. No shell file access. */
final class FileAccess {
 static final long MAX_FILE=64L*1024*1024*1024;
 static final int PORT=47183;
 private static SSLServerSocket server;
 private static ExecutorService acceptor,workers;
 private static Context app;
 private static String fingerprint;
 private static final java.util.concurrent.atomic.AtomicBoolean capturing=new java.util.concurrent.atomic.AtomicBoolean();
 static boolean wifiConnected(Context c){android.net.ConnectivityManager manager=c.getSystemService(android.net.ConnectivityManager.class);for(android.net.Network n:manager.getAllNetworks()){android.net.NetworkCapabilities caps=manager.getNetworkCapabilities(n);if(caps!=null&&caps.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI))return true;}return false;}
 private static JSONObject status(Context c)throws Exception{return new JSONObject().put("version",c.getPackageManager().getPackageInfo(c.getPackageName(),0).versionName).put("monitoring",MonitorService.running).put("wifi",wifiConnected(c)).put("helper",new ThorControls(c).helperReady()).put("capture",true).put("adaptive_control",1).put("recovery_enabled",Recovery.enabled(c)).put("recovery_paired",Recovery.paired(c)).put("recovery_permission",Recovery.permitted(c)).put("recovery_status",Recovery.state).put("file_access",enabled(c)).put("overlay_permission",LocatorStopPanel.allowed(c));}
 private static final Set<Socket> active=ConcurrentHashMap.newKeySet();
 static boolean enabled(Context c){return c.getSharedPreferences("monitor",0).getBoolean("files_enabled",false);}
 static String folder(Context c,String root){return c.getSharedPreferences("monitor",0).getString("files_"+root,"");}
 static synchronized void revoke(Context c){stop();c.getSharedPreferences("monitor",0).edit().putBoolean("files_enabled",false).remove("files_token").apply();}
 static void choose(Context c,String root,Uri uri,int flags){
  if(!root.equals("internal")&&!root.equals("sd"))throw new IllegalArgumentException();
  c.getContentResolver().takePersistableUriPermission(uri,flags&(Intent.FLAG_GRANT_READ_URI_PERMISSION|Intent.FLAG_GRANT_WRITE_URI_PERMISSION));
  String old=folder(c,root);c.getSharedPreferences("monitor",0).edit().putString("files_"+root,uri.toString()).apply();
  if(!old.isEmpty()&&!old.equals(uri.toString())&&!old.equals(folder(c,root.equals("sd")?"internal":"sd")))try{c.getContentResolver().releasePersistableUriPermission(Uri.parse(old),Intent.FLAG_GRANT_READ_URI_PERMISSION|Intent.FLAG_GRANT_WRITE_URI_PERMISSION);}catch(Exception ignored){}
 }
 static synchronized void set(Context c,boolean on)throws Exception{
  c.getSharedPreferences("monitor",0).edit().putBoolean("files_enabled",on).apply();if(on)start(c);else stop();
 }
 static synchronized void stop(){for(Socket client:active)try{client.close();}catch(Exception ignored){}active.clear();if(server!=null)try{server.close();}catch(Exception ignored){}server=null;if(acceptor!=null)acceptor.shutdownNow();if(workers!=null)workers.shutdownNow();}
 static synchronized void start(Context c)throws Exception{
  if(server!=null&&!server.isClosed())return;
  if(!enabled(c))return;
  app=c.getApplicationContext();
  KeyStore ks=KeyStore.getInstance("AndroidKeyStore");ks.load(null);String alias="thor-file-tls-ec-v1";
  if(!ks.containsAlias(alias)){
   KeyPairGenerator gen=KeyPairGenerator.getInstance("EC","AndroidKeyStore");
   gen.initialize(new KeyGenParameterSpec.Builder(alias,KeyProperties.PURPOSE_SIGN)
    .setAlgorithmParameterSpec(new java.security.spec.ECGenParameterSpec("secp256r1")).setDigests(KeyProperties.DIGEST_NONE,KeyProperties.DIGEST_SHA256,KeyProperties.DIGEST_SHA384,KeyProperties.DIGEST_SHA512)
    .setCertificateSubject(new X500Principal("CN=Thor files")).setCertificateSerialNumber(java.math.BigInteger.ONE)
    .setCertificateNotBefore(new Date(System.currentTimeMillis()-86400000)).setCertificateNotAfter(new Date(System.currentTimeMillis()+10L*365*86400000)).build());gen.generateKeyPair();
  }
  final PrivateKey key=(PrivateKey)ks.getKey(alias,null);final X509Certificate cert=(X509Certificate)ks.getCertificate(alias);
  fingerprint=hex(MessageDigest.getInstance("SHA-256").digest(cert.getEncoded()));
  X509ExtendedKeyManager km=new X509ExtendedKeyManager(){
   public String[] getClientAliases(String t,java.security.Principal[] i){return null;}public String chooseClientAlias(String[] t,java.security.Principal[] i,Socket s){return null;}
   public String[] getServerAliases(String t,java.security.Principal[] i){return "EC".equals(t)?new String[]{"thor"}:null;}
   public String chooseServerAlias(String t,java.security.Principal[] i,Socket s){return "EC".equals(t)?"thor":null;}
   public String chooseEngineServerAlias(String t,java.security.Principal[] i,SSLEngine e){return "EC".equals(t)?"thor":null;}
   public X509Certificate[] getCertificateChain(String a){return new X509Certificate[]{cert};}public PrivateKey getPrivateKey(String a){return key;}
  };
  SSLContext tls=SSLContext.getInstance("TLS");tls.init(new KeyManager[]{km},null,new SecureRandom());
  SSLServerSocket socket=(SSLServerSocket)tls.getServerSocketFactory().createServerSocket();socket.setReuseAddress(true);socket.bind(new InetSocketAddress(PORT));socket.setEnabledProtocols(new String[]{"TLSv1.2"});
  server=socket;
  android.content.SharedPreferences prefs=app.getSharedPreferences("monitor",0);
  if(!prefs.contains("files_token")){byte[] token=new byte[32];new SecureRandom().nextBytes(token);prefs.edit().putString("files_token",hex(token)).commit();}
  workers=new ThreadPoolExecutor(2,2,30,TimeUnit.SECONDS,new ArrayBlockingQueue<Runnable>(4),new ThreadPoolExecutor.AbortPolicy());
  acceptor=Executors.newSingleThreadExecutor();acceptor.execute(()->{while(!socket.isClosed()){try{SSLSocket client=(SSLSocket)socket.accept();client.setSoTimeout(15000);active.add(client);try{workers.execute(()->serve(client));}catch(Exception e){active.remove(client);client.close();}}catch(Exception e){if(socket.isClosed())break;}}});
 }
 static String hex(byte[] data){StringBuilder b=new StringBuilder();for(byte v:data)b.append(String.format(java.util.Locale.ROOT,"%02x",v&255));return b.toString();}
 static synchronized JSONObject networkSession(Context c,String id)throws Exception{
  if(!enabled(c))throw new IllegalStateException("Enable Wi-Fi access in Host settings first");start(c);return credentials(c,id);
 }
 static synchronized JSONObject session(Context c,String id)throws Exception{
  set(c,true);return credentials(c,id);
 }
 private static JSONObject credentials(Context c,String id)throws Exception{
  JSONArray hosts=new JSONArray();
  Enumeration<NetworkInterface> interfaces=NetworkInterface.getNetworkInterfaces();
  while(interfaces.hasMoreElements()){NetworkInterface n=interfaces.nextElement();if(!n.isUp()||n.isLoopback())continue;Enumeration<InetAddress> addresses=n.getInetAddresses();while(addresses.hasMoreElements()){InetAddress a=addresses.nextElement();if(a instanceof Inet4Address&&!a.isLinkLocalAddress())hosts.put(a.getHostAddress());}}
  return new JSONObject().put("ack",id).put("error","").put("files",true).put("hosts",hosts).put("port",PORT).put("pin",fingerprint).put("token",c.getSharedPreferences("monitor",0).getString("files_token",""));
 }
 private static String line(InputStream in,int max)throws IOException{ByteArrayOutputStream b=new ByteArrayOutputStream();int v;while((v=in.read())!=-1){if(v=='\n')return new String(b.toByteArray(),"US-ASCII").replace("\r","");if(b.size()>=max)throw new IOException("Header too long");b.write(v);}throw new EOFException();}
 static void reply(OutputStream out,int code,String type,long length)throws IOException{
  out.write(("HTTP/1.1 "+code+" "+(code==200?"OK":"Request failed")+"\r\nContent-Type: "+type+"\r\nContent-Length: "+length+"\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n").getBytes("US-ASCII"));
 }
 static void json(OutputStream out,int code,JSONObject value)throws IOException{byte[] bytes=value.toString().getBytes("UTF-8");reply(out,code,"application/json; charset=utf-8",bytes.length);out.write(bytes);out.flush();}
 static String[] segments(String path){if(path.length()>4096)throw new IllegalArgumentException("Path too long");if(path.isEmpty())return new String[0];String[] parts=path.split("/",-1);for(String p:parts)validateName(p);return parts;}
 static void validateName(String n){if(n.isEmpty()||n.equals(".")||n.equals("..")||n.length()>240||n.contains("/")||n.contains("\\")||n.indexOf('\0')>=0||n.contains("\r")||n.contains("\n"))throw new IllegalArgumentException("Invalid file name");}
 private static Uri tree(String root){if(!root.equals("internal")&&!root.equals("sd"))throw new IllegalArgumentException("Choose Internal or microSD");String value=folder(app,root);if(value.isEmpty())throw new IllegalStateException("Choose this folder in Thor Monitor first");return Uri.parse(value);}
 private static Uri document(Uri tree,String path)throws Exception{
  Uri current=DocumentsContract.buildDocumentUriUsingTree(tree,DocumentsContract.getTreeDocumentId(tree));
  for(String part:segments(path)){Uri next=child(tree,current,part);if(next==null)throw new FileNotFoundException("Folder or file is unavailable");current=next;}return current;
 }
 private static Uri child(Uri tree,Uri parent,String name)throws Exception{
  Uri children=DocumentsContract.buildChildDocumentsUriUsingTree(tree,DocumentsContract.getDocumentId(parent));
  try(Cursor c=app.getContentResolver().query(children,new String[]{"document_id","_display_name"},null,null,null)){if(c!=null)while(c.moveToNext())if(name.equals(c.getString(1)))return DocumentsContract.buildDocumentUriUsingTree(tree,c.getString(0));}return null;
 }
 private static Map<String,String> query(String raw)throws Exception{Map<String,String> result=new HashMap<>();if(raw!=null)for(String p:raw.split("&")){String[] kv=p.split("=",2);String k=URLDecoder.decode(kv[0],"UTF-8"),v=kv.length==2?URLDecoder.decode(kv[1],"UTF-8"):"";if(result.put(k,v)!=null)throw new IllegalArgumentException("Repeated query");}return result;}
 private static final class ResponseOutput extends FilterOutputStream {
  boolean started;
  ResponseOutput(OutputStream out){super(out);}
  @Override public void write(int b)throws IOException{started=true;out.write(b);}
  @Override public void write(byte[] b,int offset,int length)throws IOException{started=true;out.write(b,offset,length);}
 }
 private static void serve(SSLSocket socket){Uri partial=null;OutputStream out=null;android.os.PowerManager.WakeLock wake=null;
  try{
   SSLSocket client=socket;client.startHandshake();InputStream in=new BufferedInputStream(client.getInputStream());out=new ResponseOutput(client.getOutputStream());
   String[] request=line(in,8192).split(" ");if(request.length!=3||!request[2].equals("HTTP/1.1"))throw new IllegalArgumentException("Invalid request");
   Map<String,String> headers=new HashMap<>();int total=0;while(true){String h=line(in,8192);total+=h.length();if(total>16384)throw new IllegalArgumentException("Headers too large");if(h.isEmpty())break;int split=h.indexOf(':');if(split<1)throw new IllegalArgumentException();String name=h.substring(0,split).toLowerCase(Locale.ROOT);if(headers.put(name,h.substring(split+1).trim())!=null)throw new IllegalArgumentException("Duplicate header");}
   String expected="Bearer "+app.getSharedPreferences("monitor",0).getString("files_token","");
   if(!enabled(app)||!MessageDigest.isEqual(expected.getBytes("UTF-8"),headers.getOrDefault("authorization","").getBytes("UTF-8"))){json(out,401,new JSONObject().put("error","Authorize file access from the paired companion"));return;}
   if(headers.containsKey("transfer-encoding")||headers.containsKey("origin"))throw new IllegalArgumentException("Unsupported request");
   URI url=new URI(request[1]);Map<String,String> q=query(url.getRawQuery());String route=url.getPath(),method=request[0];
   wake=app.getSystemService(android.os.PowerManager.class).newWakeLock(android.os.PowerManager.PARTIAL_WAKE_LOCK,"ThorMonitor:Files");wake.acquire(30*60*1000L);
   if(method.equals("GET")&&route.equals("/v1/status")){json(out,200,status(app));return;}
   if(method.equals("GET")&&route.equals("/v1/link/read")){
    byte[] data=MonitorService.networkRead(q.getOrDefault("kind",""));json(out,200,new JSONObject().put("bytes",android.util.Base64.encodeToString(data,android.util.Base64.NO_WRAP)));return;
   }
   if(method.equals("POST")&&route.equals("/v1/link/control")){
    int size=Integer.parseInt(headers.getOrDefault("content-length","-1"));if(size<1||size>180)throw new IllegalArgumentException("Invalid command size");
    byte[] bytes=new byte[size];new DataInputStream(in).readFully(bytes);byte[] data=MonitorService.networkControl(bytes);
    json(out,200,new JSONObject().put("bytes",android.util.Base64.encodeToString(data,android.util.Base64.NO_WRAP)));return;
   }
   if(method.equals("POST")&&route.equals("/v1/capture")){
    int mode=Integer.parseInt(q.getOrDefault("mode","-1"));if(mode<0||mode>2)throw new IllegalArgumentException("Choose top, bottom or both");
    if(!wifiConnected(app))throw new IllegalStateException("Connect the Thor to Wi-Fi to capture screenshots");
    if(!new ThorControls(app).helperReady())throw new IllegalStateException("Advanced controls are unavailable. Check Recovery setup on the Thor.");
    if(!capturing.compareAndSet(false,true)){json(out,409,new JSONObject().put("error","A screenshot is already being captured"));return;}
    ScheduledExecutorService deadline=Executors.newSingleThreadScheduledExecutor();deadline.schedule(()->{try{socket.close();}catch(Exception ignored){}},90,TimeUnit.SECONDS);
    try{byte[] image=new ThorControls(app).captureImage(mode);reply(out,200,"application/x-thor-screenshot",image.length);copy(new ByteArrayInputStream(image),out,image.length);out.flush();}finally{capturing.set(false);deadline.shutdownNow();}
    return;
   }
   if(SharedFiles.enabled(app)){SharedFiles.serve(app,method,route,q,in,out,headers);return;}
   if(method.equals("GET")&&route.equals("/v1/roots")){
    JSONArray roots=new JSONArray();for(String root:new String[]{"internal","sd"}){String selected=folder(app,root);if(!selected.isEmpty()){try{Uri d=document(tree(root),"");try(Cursor c=app.getContentResolver().query(d,new String[]{"_display_name"},null,null,null)){if(c!=null&&c.moveToFirst())roots.put(new JSONObject().put("id",root).put("name",c.getString(0)));}}catch(Exception ignored){}}}
    json(out,200,new JSONObject().put("roots",roots));return;
   }
   String root=q.getOrDefault("root",""),path=q.getOrDefault("path","");Uri tree=tree(root),doc=document(tree,path);ContentResolver resolver=app.getContentResolver();
   if(method.equals("GET")&&route.equals("/v1/list")){
    int offset=Integer.parseInt(q.getOrDefault("offset","0"));if(offset<0||offset>1000000)throw new IllegalArgumentException();
    Uri children=DocumentsContract.buildChildDocumentsUriUsingTree(tree,DocumentsContract.getDocumentId(doc));JSONArray files=new JSONArray();boolean more=false;int index=0;
    try(Cursor c=resolver.query(children,new String[]{"_display_name","mime_type","_size","last_modified"},null,null,null)){if(c!=null)while(c.moveToNext()){if(index++<offset)continue;if(files.length()==200){more=true;break;}String name=c.getString(0);validateName(name);files.put(new JSONObject().put("name",name).put("dir",DocumentsContract.Document.MIME_TYPE_DIR.equals(c.getString(1))).put("size",c.isNull(2)?JSONObject.NULL:c.getLong(2)).put("modified",c.isNull(3)?JSONObject.NULL:c.getLong(3)));}}
    json(out,200,new JSONObject().put("entries",files).put("next",more?offset+files.length():-1));return;
   }
   if(method.equals("GET")&&route.equals("/v1/file")){
    long size=-1;String mime="";try(Cursor c=resolver.query(doc,new String[]{"_size","mime_type"},null,null,null)){if(c!=null&&c.moveToFirst()){if(!c.isNull(0))size=c.getLong(0);mime=c.getString(1);}}
    if(size<0||size>MAX_FILE||DocumentsContract.Document.MIME_TYPE_DIR.equals(mime))throw new IllegalArgumentException("File size is unavailable or exceeds 64 GiB");
    try(InputStream file=resolver.openInputStream(doc)){reply(out,200,"application/octet-stream",size);copy(file,out,size);}return;
   }
   if(method.equals("PUT")&&route.equals("/v1/file")){
    String name=q.getOrDefault("name","");validateName(name);long size=Long.parseLong(headers.getOrDefault("content-length","-1"));if(size<0||size>MAX_FILE)throw new IllegalArgumentException("File exceeds 64 GiB");
    if(child(tree,doc,name)!=null){json(out,409,new JSONObject().put("error","A file with this name already exists. Rename it before uploading."));return;}
    partial=DocumentsContract.createDocument(resolver,doc,"application/octet-stream",".thor-upload-"+UUID.randomUUID());if(partial==null)throw new IOException("Folder is not writable");
    try(OutputStream file=resolver.openOutputStream(partial,"w")){copy(in,file,size);file.flush();}
    if(child(tree,doc,name)!=null)throw new IOException("Destination appeared during upload; original kept");
    if(DocumentsContract.renameDocument(resolver,partial,name)==null)throw new IOException("Provider could not finalize file");partial=null;
    json(out,200,new JSONObject().put("ok",true).put("bytes",size));return;
   }
   json(out,404,new JSONObject().put("error","Unknown file operation"));
  }catch(Exception e){if(out!=null&&!((ResponseOutput)out).started)try{json(out,e instanceof SecurityException?403:400,new JSONObject().put("error",e instanceof IllegalArgumentException||e instanceof IllegalStateException||e instanceof FileNotFoundException?String.valueOf(e.getMessage()):"Transfer interrupted or folder unavailable"));}catch(Exception ignored){}
  }finally{active.remove(socket);try{socket.close();}catch(Exception ignored){}if(partial!=null)try{DocumentsContract.deleteDocument(app.getContentResolver(),partial);}catch(Exception ignored){}if(wake!=null&&wake.isHeld())wake.release();}
 }
 static void copy(InputStream in,OutputStream out,long size)throws IOException{byte[] buffer=new byte[65536];long left=size,started=android.os.SystemClock.elapsedRealtime();while(left>0){if(android.os.SystemClock.elapsedRealtime()-started>30*60*1000L)throw new IOException("Transfer time limit reached");int n=in.read(buffer,0,(int)Math.min(buffer.length,left));if(n<0)throw new EOFException("Incomplete transfer");out.write(buffer,0,n);left-=n;if(Thread.currentThread().isInterrupted())throw new IOException("Cancelled");}}
}
