package com.alan.thormonitor;

import android.app.*;
import android.content.*;
import android.os.*;
import java.io.*;
import java.net.*;
import java.security.*;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;
import javax.net.ssl.*;
import org.json.*;
import org.apache.ftpserver.*;
import org.apache.ftpserver.ftplet.*;
import org.apache.ftpserver.listener.ListenerFactory;
import org.apache.ftpserver.ssl.*;
import org.apache.ftpserver.usermanager.UsernamePasswordAuthentication;
import org.apache.ftpserver.usermanager.impl.*;

/** Optional explicit FTPS. Session credentials are memory-only and replaced on every start. */
final class FtpAccess {
    static final int PORT=47221;
    private static FtpServer server;
    private static String password="";
    private static Context app;
    private static final Map<UUID,PowerManager.WakeLock> wakes=new ConcurrentHashMap<>();
    static synchronized boolean running(){return server!=null&&!server.isStopped();}
    static synchronized void stop(){
        FtpServer old=server;server=null;password="";
        if(old!=null)old.stop();
        for(PowerManager.WakeLock w:wakes.values())if(w.isHeld())w.release();wakes.clear();
        if(app!=null)app.getSystemService(NotificationManager.class).cancel(24);
    }
    static synchronized JSONObject command(Context c,String action,String id)throws Exception{
        if(action.equals("ftp_start"))start(c);else if(action.equals("ftp_stop"))stop();else if(!action.equals("ftp_status"))throw new IllegalArgumentException("Unknown FTP action");
        JSONObject result=new JSONObject().put("ack",id).put("error","").put("running",running()).put("allowed",SharedFiles.enabled(c));
        if(running())result.put("user","thor").put("password",password).put("port",PORT).put("pin",FileAccess.certificatePin()).put("hosts",addresses());
        return result;
    }
    static JSONArray addresses()throws Exception{
        JSONArray a=new JSONArray();Enumeration<NetworkInterface> all=NetworkInterface.getNetworkInterfaces();
        while(all.hasMoreElements()){NetworkInterface n=all.nextElement();if(!n.isUp()||n.isLoopback())continue;Enumeration<InetAddress> ips=n.getInetAddresses();while(ips.hasMoreElements()){InetAddress ip=ips.nextElement();if(ip instanceof Inet4Address&&!ip.isLinkLocalAddress())a.put(ip.getHostAddress());}}
        return a;
    }
    private static synchronized void start(Context c)throws Exception{
        if(running())return;
        if(!MonitorService.running)throw new IllegalStateException("Start monitoring on the Thor first");
        if(!SharedFiles.enabled(c))throw new IllegalStateException("In Thor Monitor → Settings → Wi-Fi access, allow Shared storage permission and enable Share storage roots first.");
        app=c.getApplicationContext();byte[] secret=new byte[18];new SecureRandom().nextBytes(secret);final String credential=android.util.Base64.encodeToString(secret,android.util.Base64.NO_WRAP|android.util.Base64.URL_SAFE|android.util.Base64.NO_PADDING);
        final SSLContext tls=FileAccess.tlsContext(c);
        SslConfiguration ssl=new SslConfiguration(){
            public SSLContext getSSLContext(){return tls;}public SSLContext getSSLContext(String protocol){return tls;}
            public SSLSocketFactory getSocketFactory(){return tls.getSocketFactory();}public String[] getEnabledCipherSuites(){return null;}
            public String getEnabledProtocol(){return "TLSv1.2";}public ClientAuth getClientAuth(){return ClientAuth.NONE;}
        };
        DataConnectionConfigurationFactory data=new DataConnectionConfigurationFactory();data.setActiveEnabled(false);data.setPassiveIpCheck(true);data.setPassivePorts("47222-47231");data.setIdleTime(120);data.setSslConfiguration(ssl);
        ListenerFactory listener=new ListenerFactory();listener.setPort(PORT);listener.setIdleTimeout(300);listener.setSslConfiguration(ssl);listener.setDataConnectionConfiguration(data.createDataConnectionConfiguration());
        FtpServerFactory factory=new FtpServerFactory();factory.addListener("default",listener.createListener());
        ConnectionConfigFactory limits=new ConnectionConfigFactory();limits.setAnonymousLoginEnabled(false);limits.setMaxLogins(3);limits.setMaxLoginFailures(3);limits.setLoginFailureDelay(2);limits.setMaxThreads(4);factory.setConnectionConfig(limits.createConnectionConfig());
        BaseUser user=new BaseUser();user.setName("thor");user.setEnabled(true);user.setHomeDirectory("/");user.setMaxIdleTime(300);user.setAuthorities(Arrays.asList(new WritePermission(),new ConcurrentLoginPermission(3,3)));
        factory.setUserManager(new org.apache.ftpserver.ftplet.UserManager(){
            public User authenticate(Authentication auth)throws AuthenticationFailedException{
                if(auth instanceof UsernamePasswordAuthentication){UsernamePasswordAuthentication a=(UsernamePasswordAuthentication)auth;if("thor".equals(a.getUsername())&&a.getPassword()!=null&&MessageDigest.isEqual(credential.getBytes(java.nio.charset.StandardCharsets.UTF_8),a.getPassword().getBytes(java.nio.charset.StandardCharsets.UTF_8)))return user;}
                throw new AuthenticationFailedException("Invalid login");
            }
            public User getUserByName(String name){return "thor".equals(name)?user:null;}public String[] getAllUserNames(){return new String[]{"thor"};}
            public boolean doesExist(String name){return "thor".equals(name);}public String getAdminName(){return "";}public boolean isAdmin(String name){return false;}
            public void save(User u)throws FtpException{throw new FtpException("Session account only");}public void delete(String name)throws FtpException{throw new FtpException("Session account only");}
        });
        factory.setFileSystem(u->new FtpStorage(()->SharedFiles.roots(app)));
        factory.setFtplets(new LinkedHashMap<>(Collections.singletonMap("security",new DefaultFtplet(){
            public FtpletResult beforeCommand(FtpSession session,FtpRequest request)throws FtpException{
                String command=request.getCommand().toUpperCase(Locale.ROOT);
                if(!session.isSecure()&&!Arrays.asList("AUTH","FEAT","SYST","QUIT","NOOP","OPTS","CLNT").contains(command)){session.write(new DefaultFtpReply(534,"TLS encryption required. Use FTP with explicit TLS."));return FtpletResult.SKIP;}
                if(command.equals("CCC")||(command.equals("PROT")&&!"P".equalsIgnoreCase(request.getArgument()))){session.write(new DefaultFtpReply(534,"Encrypted control and data connections are required"));return FtpletResult.SKIP;}
                if(Arrays.asList("LIST","NLST","MLSD","RETR","STOR","APPE","STOU").contains(command)&&!session.getDataConnection().isSecure()){session.write(new DefaultFtpReply(534,"Use PROT P for encrypted transfers"));return FtpletResult.SKIP;}
                PowerManager.WakeLock wake=wakes.get(session.getSessionId());if(wake!=null)wake.acquire(2*60*60*1000L);
                return FtpletResult.DEFAULT;
            }
            public FtpletResult onLogin(FtpSession session,FtpRequest request){PowerManager.WakeLock wake=app.getSystemService(PowerManager.class).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK,"ThorMonitor:FTP");wake.setReferenceCounted(false);wake.acquire(2*60*60*1000L);wakes.put(session.getSessionId(),wake);return FtpletResult.DEFAULT;}
            public FtpletResult onDisconnect(FtpSession session){PowerManager.WakeLock wake=wakes.remove(session.getSessionId());if(wake!=null&&wake.isHeld())wake.release();return FtpletResult.DEFAULT;}
        })));
        FtpServer next=factory.createServer();try{next.start();server=next;password=credential;}catch(Exception e){next.stop();throw new IllegalStateException("Could not start FTP server; try again");}
        Intent stop=new Intent(app,MonitorService.class).setAction("STOP_FTP");PendingIntent action=PendingIntent.getService(app,24,stop,PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE);
        Notification note=new Notification.Builder(app,"monitor").setSmallIcon(android.R.drawable.stat_sys_upload).setContentTitle("FTP server running").setContentText("Tap to stop desktop file access").setContentIntent(action).setOngoing(true).addAction(new Notification.Action.Builder(null,"Stop server",action).build()).build();
        app.getSystemService(NotificationManager.class).notify(24,note);
    }
}
