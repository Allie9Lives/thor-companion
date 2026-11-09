package com.alan.thormonitor;

import android.Manifest;
import android.content.*;
import android.content.pm.PackageManager;
import android.net.*;
import android.net.nsd.*;
import android.os.*;
import android.provider.Settings;
import android.security.keystore.*;
import io.github.muntashirakon.adb.*;
import java.math.BigInteger;
import java.security.*;
import java.security.cert.Certificate;
import java.util.*;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicBoolean;
import javax.security.auth.x500.X500Principal;

/** Local TLS ADB is used only to start our fixed, UID-restricted helper. */
final class Recovery {
    private static final ExecutorService worker=Executors.newSingleThreadExecutor();
    private static final AtomicBoolean busy=new AtomicBoolean();
    private static final ScheduledExecutorService deadlines=Executors.newSingleThreadScheduledExecutor();
    static volatile int pairVersion=0;
    private static volatile boolean approvalWaiting=false;
    static volatile String state="Set up automatic recovery";
    static volatile int pairingPort=0;
    private static NsdManager.DiscoveryListener pairingDiscovery;
    static boolean permitted(Context c) { return c.checkSelfPermission(Manifest.permission.WRITE_SECURE_SETTINGS)==PackageManager.PERMISSION_GRANTED; }
    static boolean enabled(Context c) { return c.getSharedPreferences("monitor",0).getBoolean("recover_controls",false); }
    static boolean paired(Context c) { return c.getSharedPreferences("monitor",0).getBoolean("recovery_paired",false); }
    static boolean helperReady(Context c) { return new ThorControls(c).helperReady(); }
    static void enable(Context c,boolean enabled) {
        c.getSharedPreferences("monitor",0).edit().putBoolean("recover_controls",enabled).apply();
        if(enabled) {approvalWaiting=false;attempt(c);} else state="Automatic controls recovery off";
    }
    private static class LocalAdb extends AbsAdbConnectionManager {
        final PrivateKey key; final Certificate certificate;
        LocalAdb(Context app) throws Exception {
            setApi(Build.VERSION.SDK_INT);setHostAddress("127.0.0.1");setTimeout(6,TimeUnit.SECONDS);
            KeyStore store=KeyStore.getInstance("AndroidKeyStore");store.load(null);
            String alias="thor-recovery-key-encryption";
            if(!store.containsAlias(alias)) {
                javax.crypto.KeyGenerator generator=javax.crypto.KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES,"AndroidKeyStore");
                generator.init(new KeyGenParameterSpec.Builder(alias,KeyProperties.PURPOSE_ENCRYPT|KeyProperties.PURPOSE_DECRYPT)
                    .setKeySize(256).setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());
                generator.generateKey();
            }
            javax.crypto.SecretKey wrapping=(javax.crypto.SecretKey)store.getKey(alias,null);
            java.io.File file=new java.io.File(app.getFilesDir(),"recovery-key.bin");
            if(!file.exists()) {
                KeyPairGenerator generator=KeyPairGenerator.getInstance("RSA");generator.initialize(2048);java.security.KeyPair pair=generator.generateKeyPair();
                org.bouncycastle.x509.X509V3CertificateGenerator cert=new org.bouncycastle.x509.X509V3CertificateGenerator();
                X500Principal subject=new X500Principal("CN=Thor Monitor");
                cert.setSubjectDN(subject);cert.setIssuerDN(subject);cert.setSerialNumber(new BigInteger(128,new SecureRandom()));
                cert.setNotBefore(new Date(System.currentTimeMillis()-86400000));cert.setNotAfter(new Date(System.currentTimeMillis()+10L*365*86400000L));
                cert.setPublicKey(pair.getPublic());cert.setSignatureAlgorithm("SHA256withRSA");
                Certificate publicCert=cert.generate(pair.getPrivate());
                javax.crypto.Cipher cipher=javax.crypto.Cipher.getInstance("AES/GCM/NoPadding");cipher.init(javax.crypto.Cipher.ENCRYPT_MODE,wrapping);
                byte[] encoded=pair.getPrivate().getEncoded(),sealed=cipher.doFinal(encoded);java.util.Arrays.fill(encoded,(byte)0);
                java.io.File tmp=new java.io.File(app.getFilesDir(),"recovery-key.tmp");
                try(java.io.DataOutputStream out=new java.io.DataOutputStream(new java.io.FileOutputStream(tmp))) {
                    out.writeInt(cipher.getIV().length);out.write(cipher.getIV());out.writeInt(sealed.length);out.write(sealed);out.write(publicCert.getEncoded());out.flush();
                }
                if(!tmp.renameTo(file))throw new java.io.IOException("Could not save recovery identity");
            }
            try(java.io.DataInputStream in=new java.io.DataInputStream(new java.io.FileInputStream(file))) {
                int ivLength=in.readInt();if(ivLength!=12)throw new java.io.IOException("Invalid key data");byte[] iv=new byte[ivLength];in.readFully(iv);
                int sealedLength=in.readInt();if(sealedLength<256||sealedLength>8192)throw new java.io.IOException("Invalid key data");byte[] sealed=new byte[sealedLength];in.readFully(sealed);
                javax.crypto.Cipher cipher=javax.crypto.Cipher.getInstance("AES/GCM/NoPadding");cipher.init(javax.crypto.Cipher.DECRYPT_MODE,wrapping,new javax.crypto.spec.GCMParameterSpec(128,iv));
                byte[] encoded=cipher.doFinal(sealed);
                try {key=KeyFactory.getInstance("RSA").generatePrivate(new java.security.spec.PKCS8EncodedKeySpec(encoded));}
                finally {java.util.Arrays.fill(encoded,(byte)0);}
                certificate=java.security.cert.CertificateFactory.getInstance("X.509").generateCertificate(in);
            }
        }
        @Override public void close() throws java.io.IOException { disconnect(); }
        @Override protected PrivateKey getPrivateKey() {return key;}
        @Override protected Certificate getCertificate() {return certificate;}
        @Override protected String getDeviceName() {return "Thor Monitor";}
    }
    static void pair(Context context,int port,String code) {
        Context c=context.getApplicationContext();
        if(port<1 || port>65535 || !code.matches("[0-9]{6}")) {state="Enter the pairing port and six-digit code";return;}
        if(!busy.compareAndSet(false,true)) return;
        worker.execute(()->{
            state="Pairing with this Thor…";
            boolean success=false;
            try(LocalAdb adb=new LocalAdb(c)) {
                if(!adb.pair("127.0.0.1",port,code)) throw new IllegalStateException("Pairing rejected");
                c.getSharedPreferences("monitor",0).edit().putBoolean("recovery_paired",true).putBoolean("recover_controls",true).apply();
                state="Paired · restoring controls";success=true;++pairVersion;
                log(c,"recovery_paired", "Local wireless-debugging pairing saved");
            } catch(Exception e) {state="Pairing failed. Open a fresh pairing code and try again.";log(c,"recovery_pair_failed",e.getClass().getSimpleName());}
            finally {busy.set(false);}
            if(success) attempt(c);
        });
    }
    static void attempt(Context context) {
        Context c=context.getApplicationContext();
        if(!enabled(c) || !busy.compareAndSet(false,true)) return;
        worker.execute(()->{
            PowerManager.WakeLock lock=c.getSystemService(PowerManager.class).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK,"com.alan.thormonitor:Recovery");
            lock.acquire(30000);
            try {
                if(!paired(c)) {state="Pair wireless debugging once to enable recovery";return;}
                if(!permitted(c) && Settings.Global.getInt(c.getContentResolver(),"adb_wifi_enabled",0)==0) {
                    state="Turn on wireless debugging to finish the one-time setup";return;
                }
                if(helperReady(c) && permitted(c)) {state="Advanced controls ready";return;}
                // Android's wireless-debugging service handles Wi-Fi readiness and network approval.
                // A default-network test incorrectly rejects local-only and vendor-managed Wi-Fi.
                if(approvalWaiting && Settings.Global.getInt(c.getContentResolver(),"adb_wifi_enabled",0)==0){state="Check wireless debugging and its network approval, then tap Retry now";return;}
                boolean wifiConnectedAtRequest=false;
                ConnectivityManager connectivity=c.getSystemService(ConnectivityManager.class);
                for(Network network:connectivity.getAllNetworks()){NetworkCapabilities caps=connectivity.getNetworkCapabilities(network);if(caps!=null&&caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)){wifiConnectedAtRequest=true;break;}}
                state="Restoring advanced controls…";
                if(permitted(c))Settings.Global.putInt(c.getContentResolver(),"adb_wifi_enabled",1);
                int port=discoverConnectPort(c);
                if(port<1) {
                    // Wi-Fi may connect while discovery waits. Do not mistake that
                    // boot-time transition for rejection of a network-approval prompt.
                    approvalWaiting=wifiConnectedAtRequest&&Settings.Global.getInt(c.getContentResolver(),"adb_wifi_enabled",0)==0;
                    state="Waiting for wireless debugging. Check Wi-Fi and its network approval.";return;
                }
                try(LocalAdb adb=new LocalAdb(c)) {
                    if(!adb.connect("127.0.0.1",port)) throw new IllegalStateException("Connection unavailable");
                    if(!permitted(c)) {
                        state="Completing one-time recovery permission…";
                        String pkg=c.getPackageName();if(!pkg.matches("[A-Za-z0-9_.]+"))throw new IllegalStateException("Invalid package");
                        ScheduledFuture<?> grantDeadline=deadlines.schedule(()->{try{adb.disconnect();}catch(Exception ignored){}},8,TimeUnit.SECONDS);
                        try(AdbStream stream=adb.openStream("shell:/system/bin/pm grant "+pkg+" android.permission.WRITE_SECURE_SETTINGS")) {
                            byte[] ignored=new byte[256];while(stream.openInputStream().read(ignored)!=-1){}
                        }catch(java.io.IOException ignored){} // Recheck the actual permission, not shell output.
                        finally {grantDeadline.cancel(false);}
                        for(int i=0;i<20&&!permitted(c);i++)Thread.sleep(100);
                        if(!permitted(c))throw new IllegalStateException("One-time permission was not granted; see setup help");
                        log(c,"recovery_permission_ready","Permission granted through on-device paired ADB");
                    }
                    if(helperReady(c)){state="Advanced controls ready";return;}
                    String apk=c.getApplicationInfo().sourceDir;
                    if(!apk.matches("/data/app/[A-Za-z0-9_+=/~.-]+/base\\.apk")) throw new IllegalStateException("Unexpected app location");
                    String name=ThorControls.socketName(c);
                    if(!name.matches("thor-controls-[a-f0-9]{32}"))throw new IllegalStateException("Invalid local endpoint");
                    int outdated=ThorControls.outdatedHelperPid(c);
                    String replace=outdated>1?"/system/bin/kill "+outdated+"; sleep 0.2; ":"";
                    String command=replace+"CLASSPATH='"+apk+"' /system/bin/setsid /system/bin/nohup /system/bin/app_process /system/bin --nice-name=thor-control-helper com.alan.thormonitor.ControlHelper "+name+" "+android.os.Process.myUid()+" </dev/null >/data/local/tmp/thor-control-helper.log 2>&1 & sleep 1";
                    ScheduledFuture<?> deadline=deadlines.schedule(()->{try{adb.disconnect();}catch(Exception ignored){}},8,TimeUnit.SECONDS);
                    java.io.IOException streamFailure=null;
                    try(AdbStream stream=adb.openStream("shell:"+command)) {
                        byte[] buffer=new byte[128];while(stream.openInputStream().read(buffer)!=-1) {} // Fixed command only, output is not retained.
                    } catch(java.io.IOException e) {streamFailure=e;}
                    finally {deadline.cancel(false);}
                    for(int i=0;i<30 && !helperReady(c);i++) Thread.sleep(100);
                    if(!helperReady(c)) {if(streamFailure!=null)throw streamFailure;throw new IllegalStateException("Helper did not start");}
                    state="Advanced controls ready";log(c,"controls_recovered","Helper restarted through local TLS ADB");
                }
            } catch(Exception e) {
                if(helperReady(c)) {state="Advanced controls ready";log(c,"controls_recovered","Helper verified after local TLS stream closed");}
                else {state="Recovery will retry. Check wireless debugging if controls stay unavailable.";log(c,"recovery_retry",e.getClass().getSimpleName()+": "+String.valueOf(e.getMessage()));}
            } finally {if(lock.isHeld())lock.release();busy.set(false);}
        });
    }
    static void networkAvailable(Context c) {approvalWaiting=false;attempt(c);}
    private static int discoverConnectPort(Context c) throws Exception {
        // Some Thor firmware does not announce its own connect service over mDNS.
        // This property is written by adbd; only a loopback connection is made.
        try {
            java.lang.Process process=new ProcessBuilder("/system/bin/getprop","service.adb.tls.port").start();
            if(process.waitFor(1,TimeUnit.SECONDS)) {
                String value=new java.io.BufferedReader(new java.io.InputStreamReader(process.getInputStream())).readLine();
                int port=Integer.parseInt(value==null?"0":value.trim());
                if(port>0 && port<=65535)return port;
            } else process.destroyForcibly();
        }catch(Exception ignored){}

        NsdManager manager=c.getSystemService(NsdManager.class);ArrayBlockingQueue<Integer> found=new ArrayBlockingQueue<>(4);
        NsdManager.DiscoveryListener listener=discovery(manager,found);
        manager.discoverServices("_adb-tls-connect._tcp",NsdManager.PROTOCOL_DNS_SD,listener);
        try {Integer port=found.poll(12,TimeUnit.SECONDS);return port==null?0:port;}
        finally {try{manager.stopServiceDiscovery(listener);}catch(Exception ignored){}}
    }
    private static NsdManager.DiscoveryListener discovery(NsdManager manager,BlockingQueue<Integer> found) {
        return new NsdManager.DiscoveryListener() {
            public void onDiscoveryStarted(String t){}
            public void onDiscoveryStopped(String t){}
            public void onStartDiscoveryFailed(String t,int e){}
            public void onStopDiscoveryFailed(String t,int e){}
            public void onServiceLost(NsdServiceInfo s){}
            public void onServiceFound(NsdServiceInfo service) {
                manager.resolveService(service,new NsdManager.ResolveListener(){
                    public void onResolveFailed(NsdServiceInfo s,int e){}
                    public void onServiceResolved(NsdServiceInfo s){
                        try {if(s.getPort()>0 && (s.getHost().isLoopbackAddress() || java.net.NetworkInterface.getByInetAddress(s.getHost())!=null))found.offer(s.getPort());}catch(Exception ignored){}
                    }
                });
            }
        };
    }
    static void watchPairing(Context c) {
        stopPairingDiscovery(c);
        NsdManager manager=c.getSystemService(NsdManager.class);
        BlockingQueue<Integer> found=new LinkedBlockingQueue<Integer>() {
            @Override public boolean offer(Integer port) {pairingPort=port;return true;}
        };
        pairingDiscovery=discovery(manager,found);
        try {manager.discoverServices("_adb-tls-pairing._tcp",NsdManager.PROTOCOL_DNS_SD,pairingDiscovery);}
        catch(Exception e){state="Enter the port shown in the pairing window";}
    }
    static void stopPairingDiscovery(Context c) {
        if(pairingDiscovery!=null)try{c.getSystemService(NsdManager.class).stopServiceDiscovery(pairingDiscovery);}catch(Exception ignored){}
        pairingDiscovery=null;pairingPort=0;
    }
    private static void log(Context c,String event,String detail) {
        try{Telemetry.log(c,event,new org.json.JSONObject().put("detail",detail));}catch(Exception ignored){}
    }
}
