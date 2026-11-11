package com.alan.thormonitor;

import android.app.*;
import android.bluetooth.*;
import android.bluetooth.le.*;
import android.content.*;
import android.os.*;
import org.json.JSONObject;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.*;

public class MonitorService extends Service {
    static volatile ActivityMonitor activity;
    private static volatile MonitorService instance;
    static void locatorChanged(){MonitorService service=instance;if(service!=null)service.timeoutHandler.post(()->{if(!service.closing&&running){service.notifySubscribers();}});}
    private final Telemetry telemetry = new Telemetry();
    public static volatile String state = "Monitoring stopped";
    public static volatile long sequence = 0, lastSample = 0;
    public static volatile int connections = 0;
    public static volatile boolean running = false;
    public static volatile boolean continuous = false;
    private boolean bluetoothStarting = false, monitoringStarted = false;
    private volatile int gattEpoch;
    private AdvertiseCallback currentAdvertisingCallback;
    private final android.net.ConnectivityManager.NetworkCallback networkCallback=new android.net.ConnectivityManager.NetworkCallback(){
        private android.net.Network lastWifi;
        @Override public void onCapabilitiesChanged(android.net.Network network,android.net.NetworkCapabilities caps){
            if(caps.hasTransport(android.net.NetworkCapabilities.TRANSPORT_WIFI)&&!network.equals(lastWifi)){lastWifi=network;if(powerSaving!=null){powerSaving.invalidateNetwork();if(timer!=null)timer.execute(()->evaluatePower());}Recovery.networkAvailable(MonitorService.this);}
        }
        @Override public void onLost(android.net.Network network){if(network.equals(lastWifi)){lastWifi=null;if(powerSaving!=null){powerSaving.invalidateNetwork();if(timer!=null)timer.execute(()->evaluatePower());}}}
    };
    public static volatile long activeUntil = 0;
    private static final long TEST_MS = 10 * 60 * 1000;
    private PowerManager.WakeLock testWakeLock;
    private final Handler timeoutHandler = new Handler(Looper.getMainLooper());
    private final Runnable testTimeout = () -> {
        event("active_test_expired", "10-minute test deadline reached");
        stopSelf();
    };
    static final UUID BATTERY = uuid("180f"), LEVEL = uuid("2a19"), CCC = uuid("2902"), DESCRIPTION = uuid("2901");
    static final UUID SERVICE = UUID.fromString("a7b31000-8427-4c35-9d6a-9af7b6729e01");
    static final UUID STATS = UUID.fromString("a7b31001-8427-4c35-9d6a-9af7b6729e01");
    static final UUID LIVE = UUID.fromString("a7b31002-8427-4c35-9d6a-9af7b6729e01");
    static final UUID HARDWARE = UUID.fromString("a7b31003-8427-4c35-9d6a-9af7b6729e01");
    static final UUID CONTROL_SERVICE=UUID.fromString("a7b32000-8427-4c35-9d6a-9af7b6729e01");
    static final UUID CONTROL=UUID.fromString("a7b32001-8427-4c35-9d6a-9af7b6729e01");
    private ThorControls controls;private PowerSaving powerSaving;private long restResumeToken;
    private BluetoothGattServer server;
    private BluetoothLeAdvertiser advertiser;
    private BluetoothGattCharacteristic battery, stats, live, hardware;
    private ScheduledExecutorService timer;
    private volatile JSONObject latest;
    private volatile boolean closing;
    private final Map<String, BluetoothDevice> devices = new ConcurrentHashMap<>();
    private final Map<String, Integer> mtus = new ConcurrentHashMap<>();
    private final Set<String> subscriptions = ConcurrentHashMap.newKeySet();
    private final Map<String, byte[]> readSnapshots = new ConcurrentHashMap<>();

    private static UUID uuid(String shortId) { return UUID.fromString("0000" + shortId + "-0000-1000-8000-00805f9b34fb"); }
    private void event(String name, String detail) {
        try { Telemetry.log(this, name, new JSONObject().put("detail", detail)); } catch (Exception ignored) {}
    }

    @Override public void onCreate() {
        super.onCreate();
        instance=this;
        FindThor.recoverVolume(this);
        testWakeLock = getSystemService(PowerManager.class).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "com.alan.thormonitor:ClosedLidTest");
        testWakeLock.setReferenceCounted(false);
        NotificationManager nm = getSystemService(NotificationManager.class);
        nm.createNotificationChannel(new NotificationChannel("monitor", "Thor monitoring", NotificationManager.IMPORTANCE_LOW));
        startForeground(1, notification("Starting Bluetooth monitoring"));
        running = true;
        registerReceiver(screenReceiver, new IntentFilter(Intent.ACTION_SCREEN_OFF));
        registerReceiver(screenReceiver, new IntentFilter(Intent.ACTION_SCREEN_ON));
        registerReceiver(screenReceiver,new IntentFilter(PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED));
        registerReceiver(bondReceiver, new IntentFilter(BluetoothDevice.ACTION_BOND_STATE_CHANGED));
        controls = new ThorControls(this);powerSaving=new PowerSaving(this);
        registerReceiver(radioReceiver,new IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED));
        try {getSystemService(android.net.ConnectivityManager.class).registerNetworkCallback(new android.net.NetworkRequest.Builder().addTransportType(android.net.NetworkCapabilities.TRANSPORT_WIFI).build(),networkCallback);}catch(Exception ignored){}
        activity=new ActivityMonitor(this);
        capture("start");
        try{FileAccess.start(this);}catch(Exception e){event("files_unavailable",e.getClass().getSimpleName());}
        timer=Executors.newSingleThreadScheduledExecutor();
        timer.scheduleWithFixedDelay(()->{
            try {
                if(activeUntil>0 && SystemClock.elapsedRealtime()>=activeUntil){stopSelf();return;}
                capture("timer");activity.sample(latest);evaluatePower();notifySubscribers();Recovery.attempt(this);
                if(server==null)timeoutHandler.post(()->startBluetooth());
            }catch(Exception e){event("sample_error",e.getClass().getSimpleName());}
        },30,30,TimeUnit.SECONDS);
        startBluetooth();
        registerReceiver(batteryReceiver,new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
    }
    private synchronized void startBluetooth() {
        if(closing || server!=null || bluetoothStarting)return;
        if(checkSelfPermission(android.Manifest.permission.BLUETOOTH_CONNECT)!=android.content.pm.PackageManager.PERMISSION_GRANTED || checkSelfPermission(android.Manifest.permission.BLUETOOTH_ADVERTISE)!=android.content.pm.PackageManager.PERMISSION_GRANTED){state="Bluetooth permission needed";return;}
        BluetoothAdapter adapter=getSystemService(BluetoothManager.class).getAdapter();
        if(adapter==null || !adapter.isEnabled()) {state="Turn on Bluetooth to connect your phone";return;}
        bluetoothStarting=true;
        try {
            advertiser=adapter.getBluetoothLeAdvertiser();
            if(advertiser==null)throw new IllegalStateException("Bluetooth advertising unavailable");
            server=getSystemService(BluetoothManager.class).openGattServer(this,newCallback(++gattEpoch));
            if(server==null)throw new IllegalStateException("Bluetooth service unavailable");
            battery=characteristic(LEVEL,"Battery Level",true);
            stats=characteristic(STATS,"Device stats (UTF-8 JSON)",false);
            live=characteristic(LIVE,"Live status (UTF-8; every 30 seconds while CPU runs)",true);
            hardware=characteristic(HARDWARE,"Hardware (UTF-8 JSON)",false);
            BluetoothGattService service=new BluetoothGattService(BATTERY,BluetoothGattService.SERVICE_TYPE_PRIMARY);
            service.addCharacteristic(battery);
            if(!server.addService(service))throw new IllegalStateException("Could not add battery service");
        }catch(Exception e){state="Bluetooth unavailable · retrying";event("bluetooth_retry",e.getClass().getSimpleName());closeBluetooth();}
        finally{bluetoothStarting=false;}
    }
    private synchronized void closeBluetooth() {
        ++gattEpoch;
        try{if(advertiser!=null)advertiser.stopAdvertising(currentAdvertisingCallback);}catch(Exception ignored){}
        try{if(server!=null)server.close();}catch(Exception ignored){}
        timeoutHandler.post(MonitorService.this::resetNotifications);
        server=null;advertiser=null;devices.clear();subscriptions.clear();mtus.clear();readSnapshots.clear();connections=0;
    }
    private final BroadcastReceiver radioReceiver=new BroadcastReceiver(){
        public void onReceive(Context c,Intent i){
            if(i.getIntExtra(BluetoothAdapter.EXTRA_STATE,-1)==BluetoothAdapter.STATE_ON)startBluetooth();
            else if(i.getIntExtra(BluetoothAdapter.EXTRA_STATE,-1)==BluetoothAdapter.STATE_OFF){closeBluetooth();state="Turn on Bluetooth to connect your phone";}
        }
    };

    private BluetoothGattCharacteristic characteristic(UUID id, String name, boolean notify) {
        BluetoothGattCharacteristic c = new BluetoothGattCharacteristic(id,
            BluetoothGattCharacteristic.PROPERTY_READ | (notify ? BluetoothGattCharacteristic.PROPERTY_NOTIFY : 0),
            BluetoothGattCharacteristic.PERMISSION_READ_ENCRYPTED_MITM);
        BluetoothGattDescriptor label = new BluetoothGattDescriptor(DESCRIPTION, BluetoothGattDescriptor.PERMISSION_READ);
        label.setValue(name.getBytes(StandardCharsets.UTF_8)); c.addDescriptor(label);
        if (notify) c.addDescriptor(new BluetoothGattDescriptor(CCC,
            BluetoothGattDescriptor.PERMISSION_READ_ENCRYPTED_MITM | BluetoothGattDescriptor.PERMISSION_WRITE_ENCRYPTED_MITM));
        return c;
    }

    private synchronized JSONObject capture(String reason) {
        latest = telemetry.sample(this, ++sequence); lastSample = latest.optLong("sampled_at_ms");
        try {
            latest.put("locator_active",FindThor.ringing).put("keep_alive_paused",powerSaving!=null&&powerSaving.suspended);
            latest.put("wake_lock_held", testWakeLock != null && testWakeLock.isHeld());
            latest.put("active_test_remaining_ms", Math.max(0, activeUntil - SystemClock.elapsedRealtime()));
        } catch (Exception ignored) {}
        try{BatteryHistory.get(this).record(latest);}catch(Exception ignored){}
        Telemetry.log(this, "sample_" + reason, latest);
        return latest;
    }

    static byte[] networkRead(String kind) throws Exception {
        MonitorService s=instance;if(s==null||s.closing||!running)throw new IllegalStateException("Start monitoring on the Thor");
        if(kind.equals("control"))return s.controls.snapshot().toString().getBytes(StandardCharsets.UTF_8);
        UUID id=kind.equals("stats")?STATS:kind.equals("hardware")?HARDWARE:kind.equals("live")?LIVE:null;
        if(id==null)throw new IllegalArgumentException("Unknown reading");
        return s.value(id,s.capture("network_read"));
    }
    static byte[] networkControl(byte[] bytes)throws Exception {
        MonitorService s=instance;if(s==null||s.closing||!running)throw new IllegalStateException("Start monitoring on the Thor");
        return s.controls.exchange(bytes).toString().getBytes(StandardCharsets.UTF_8);
    }

    private synchronized void evaluatePower(){
        if(closing||activeUntil>0||powerSaving==null)return;
        boolean wasPaused=getSharedPreferences("monitor",0).getBoolean("rest_suspended",false);
        continuous=getSharedPreferences("monitor",0).getBoolean("always_on",true);
        long token=getSharedPreferences("monitor",0).getLong("rest_resume_token",0);if(token>restResumeToken){restResumeToken=token;powerSaving.resume();}
        Boolean closed=null;try{JSONObject a=activity.reply("power");if(!a.isNull("lid"))closed=a.getBoolean("lid");}catch(Exception ignored){}
        boolean pause=powerSaving.evaluate(getSystemService(PowerManager.class).isInteractive(),closed);
        if(continuous&&!pause){if(!testWakeLock.isHeld())testWakeLock.acquire();}else if(testWakeLock.isHeld())testWakeLock.release();
        if(wasPaused!=pause){capture("power_policy");notifySubscribers();}
        getSystemService(NotificationManager.class).notify(1,notification(pause?"Battery saving · keep-alive paused; restore "+PowerSaving.clock(powerSaving.end()):continuous?"Monitoring · CPU keep-alive active":"Passive monitoring · CPU may sleep"));
    }
    static void restChanged(){MonitorService s=instance;if(s!=null&&!s.closing&&s.timer!=null)s.timer.execute(()->s.evaluatePower());}
    static void restPower(int action){MonitorService s=instance;if(s==null||s.powerSaving==null)throw new IllegalStateException("Start monitoring first");synchronized(s){if(action==4)s.powerSaving.manual();else s.powerSaving.resume();s.evaluatePower();}}

    private Notification notification(String text) {
        PendingIntent open = PendingIntent.getActivity(this, 0, new Intent(this, MainActivity.class), PendingIntent.FLAG_IMMUTABLE);
        PendingIntent stop = PendingIntent.getService(this, 1, new Intent(this, MonitorService.class).setAction("STOP"), PendingIntent.FLAG_IMMUTABLE);
        return new Notification.Builder(this, "monitor").setContentTitle("Thor Monitor")
            .setContentText(text).setSmallIcon(android.R.drawable.stat_sys_data_bluetooth).setOngoing(true)
            .setContentIntent(open).addAction(new Notification.Action.Builder(null, "Stop", stop).build()).build();
    }

    private void advertise() {
        AdvertiseSettings settings = new AdvertiseSettings.Builder().setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_POWER)
            .setConnectable(true).setTimeout(0).setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM).build();
        AdvertiseData data = new AdvertiseData.Builder().addServiceUuid(new ParcelUuid(SERVICE)).build();
        AdvertiseData response = new AdvertiseData.Builder().setIncludeDeviceName(true).build();
        currentAdvertisingCallback=newAdvertisingCallback(gattEpoch);
        advertiser.startAdvertising(settings, data, response, currentAdvertisingCallback);
    }

    private AdvertiseCallback newAdvertisingCallback(final int epoch) { return new AdvertiseCallback() {
        @Override public void onStartSuccess(AdvertiseSettings s) {
            if (closing || epoch!=gattEpoch) return;
            state = "Bluetooth ready · scan for Thor"; event("advertising_started", "success");
            getSystemService(NotificationManager.class).notify(1, notification(activeUntil > 0 ? "10-minute test · CPU awake, screens may sleep" : continuous ? "Monitoring · stays active with the lid closed" : "Bluetooth ready · waiting for your phone"));
        }
        @Override public void onStartFailure(int code) {
            if(closing || epoch!=gattEpoch)return;
            state = "Bluetooth advertising failed (" + code + ")"; event("advertising_failed", "code=" + code); closeBluetooth();
        }
    }; }

    private final PhoneRepairGate repairGate=new PhoneRepairGate();
    private final Map<String,BluetoothDevice> repairPeers=new LinkedHashMap<>();
    static List<BluetoothDevice> repairCandidates(){MonitorService s=instance;return s==null?Collections.emptyList():s.pendingPhones();}
    private synchronized List<BluetoothDevice> pendingPhones(){
        long now=SystemClock.elapsedRealtime();
        repairPeers.entrySet().removeIf(e->!repairGate.contains(e.getKey(),now));
        List<BluetoothDevice> result=new ArrayList<>();
        for(BluetoothDevice d:repairPeers.values())if(d.getBondState()==BluetoothDevice.BOND_BONDED)result.add(d);
        return result;
    }
    static boolean approvePhoneRepair(String address){MonitorService s=instance;return s!=null&&s.replacePhone(address);}
    private synchronized boolean replacePhone(String address){
        BluetoothDevice d=repairPeers.get(address);
        if(closing||d==null||d.getBondState()!=BluetoothDevice.BOND_BONDED||!repairGate.contains(address,SystemClock.elapsedRealtime()))return false;
        if(!getSharedPreferences("monitor",0).edit().putString("owner",address).commit())return false;
        FileAccess.revoke(this);
        subscriptions.clear();readSnapshots.clear();repairGate.clear();repairPeers.clear();
        event("phone_repair_approved","Authorized phone replaced with local approval; network access revoked");
        return true;
    }

    private synchronized boolean authorized(BluetoothDevice device) {
        if (device.getBondState() != BluetoothDevice.BOND_BONDED) return false;
        String owner = getSharedPreferences("monitor", 0).getString("owner", "");
        if (owner.isEmpty()) {
            getSharedPreferences("monitor", 0).edit().putString("owner", device.getAddress()).commit();
            event("phone_authorized", "First bonded phone authorized"); return true;
        }
        if(owner.equals(device.getAddress()))return true;
        long now=SystemClock.elapsedRealtime();
        repairPeers.entrySet().removeIf(e->!repairGate.contains(e.getKey(),now));
        if(repairGate.record(device.getAddress(),now))event("phone_repair_needed","Bonded peer does not match saved authorized phone; local approval required");
        repairPeers.put(device.getAddress(),device);
        while(repairPeers.size()>8)repairPeers.remove(repairPeers.keySet().iterator().next());
        return false;
    }

    private byte[] value(UUID id, JSONObject j) {
        if (id.equals(LEVEL)) return new byte[]{(byte) j.optInt("battery_percent", 0)};
        if (id.equals(LIVE)) return ("n=" + j.optLong("sequence") + " b=" + j.optInt("battery_percent", 0)).getBytes(StandardCharsets.UTF_8);
        JSONObject result = new JSONObject();
        try {
            if (id.equals(STATS)) {
                String[][] keys = {{"keep_alive_paused","keep_alive_paused"},{"locator_active","locator_active"},{"full_uah","full_charge_uah"},{"design_uah","design_charge_uah"},{"cycles","cycle_count"},{"health","battery_health_code"},{"seq","sequence"},{"ts_ms","sampled_at_ms"},{"battery_pct","battery_percent"},
                    {"temp_c","battery_temperature_c"},{"voltage_mv","battery_voltage_mv"},{"current_ua_raw","current_ua_raw"},
                    {"charge_uah","charge_counter_uah"},{"status_code","battery_status_code"},{"plugged_code","plugged_code"},
                    {"interactive","interactive"},{"idle","device_idle"},{"free_bytes","data_available_bytes"},
                    {"cpu_pct","cpu_percent"},{"cpu_window_ms","cpu_window_ms"},{"gpu_pct","gpu_percent"},
                    {"ram_free_bytes","ram_available_bytes"},{"sd_state","sd_state"},
                    {"sd_total_bytes","sd_total_bytes"},{"sd_free_bytes","sd_available_bytes"},
                    {"input_w","input_watts"}};
                for (String[] key : keys) result.put(key[0], j.opt(key[1]));
            } else if (id.equals(HARDWARE)) {
                for (String key : new String[]{"model","device_name","variant","soc_model","storage_capacity_bytes","manufacturer","android","build","cpu_name","gpu_name","ram_total_bytes","data_total_bytes","storage_model","ufs_descriptor","ufs_version"})
                    result.put(key, j.opt(key));
            }
        } catch (Exception ignored) {}
        return result.toString().getBytes(StandardCharsets.UTF_8);
    }

    private static final class PendingNotification {
        final BluetoothDevice device;final BluetoothGattCharacteristic characteristic;final byte[] bytes;
        final Runnable delivered;final boolean screenshot;
        PendingNotification(BluetoothDevice d,BluetoothGattCharacteristic c,byte[] b,Runnable done,boolean shot){device=d;characteristic=c;bytes=b;delivered=done;screenshot=shot;}
    }
    // All notification queue access runs on the service's main handler. Only one
    // ATT notification is outstanding, including normal battery/live updates.
    private final ArrayDeque<PendingNotification> notifications=new ArrayDeque<>();
    private PendingNotification notificationInFlight;
    private Integer screenshotToken;
    private PowerManager.WakeLock screenshotWakeLock;
    private void releaseScreenshotWakeLock(){if(screenshotWakeLock!=null && screenshotWakeLock.isHeld())screenshotWakeLock.release();}
    private final Runnable notificationTimeout=()->{event("notification_timeout","Stopping unresponsive transfer");resetNotifications();closeBluetooth();};
    private void resetNotifications(){
        timeoutHandler.removeCallbacks(notificationTimeout);notifications.clear();notificationInFlight=null;screenshotToken=null;releaseScreenshotWakeLock();
        if(controls!=null){controls.clearShot();controls.clearHistoryReply();}
    }
    private void enqueueNotification(PendingNotification n){notifications.add(n);pumpNotifications();}
    private void pumpNotifications(){
        if(notificationInFlight!=null || notifications.isEmpty() || closing || server==null)return;
        PendingNotification n=notifications.remove();
        if(!devices.containsKey(n.device.getAddress()) || !authorizedWithoutClaim(n.device)){resetNotifications();return;}
        notificationInFlight=n;
        int result=server.notifyCharacteristicChanged(n.device,n.characteristic,false,n.bytes);
        if(result!=0){event("notification_error","Bluetooth rejected notification");resetNotifications();return;}
        timeoutHandler.postDelayed(notificationTimeout,8000);
    }
    private void notificationDelivered(int status){
        timeoutHandler.removeCallbacks(notificationTimeout);
        PendingNotification n=notificationInFlight;notificationInFlight=null;
        if(n==null)return;
        if(status!=0){event("notification_error","Bluetooth delivery failed");resetNotifications();return;}
        if(!n.screenshot)event("notification_sent","status=0");
        if(n.delivered!=null)n.delivered.run();
        pumpNotifications();
    }
    private void notifySubscribers() {
        JSONObject sample=latest;
        timeoutHandler.post(()->{
            if(server==null || battery==null || live==null || screenshotToken!=null)return;
            for(BluetoothDevice device:devices.values()) {
                if(!authorizedWithoutClaim(device))continue;
                for(BluetoothGattCharacteristic c:new BluetoothGattCharacteristic[]{battery,live})
                    if(subscriptions.contains(device.getAddress()+c.getUuid()))
                        enqueueNotification(new PendingNotification(device,c,value(c.getUuid(),sample),null,false));
            }
        });
    }
    private void streamScreenshot(BluetoothDevice device){
        CaptureBuffer image=controls.screenshot();
        if(image==null || !subscriptions.contains(device.getAddress()+LIVE) || mtus.getOrDefault(device.getAddress(),23)<40){controls.clearShot();return;}
        screenshotToken=image.token;
        releaseScreenshotWakeLock();
        screenshotWakeLock=getSystemService(PowerManager.class).newWakeLock(PowerManager.PARTIAL_WAKE_LOCK,"ThorMonitor:Screenshot");
        screenshotWakeLock.acquire(300000);
        event("screenshot_stream","Sending screenshot to paired phone");
        enqueueScreenshot(device,image,0);
    }
    private void enqueueScreenshot(BluetoothDevice device,CaptureBuffer image,int offset){
        if(screenshotToken==null || screenshotToken!=image.token || controls.screenshot()!=image){screenshotToken=null;releaseScreenshotWakeLock();return;}
        byte[] packet=image.packet(offset,mtus.getOrDefault(device.getAddress(),23));
        enqueueNotification(new PendingNotification(device,live,packet,()->{
            int next=offset+packet.length-16;
            if(next==image.bytes.length){controls.clearShot();screenshotToken=null;releaseScreenshotWakeLock();event("screenshot_delivered","Capture released from memory");}
            else enqueueScreenshot(device,image,next);
        },true));
    }

    private boolean authorizedWithoutClaim(BluetoothDevice d) {
        return d.getBondState() == BluetoothDevice.BOND_BONDED && d.getAddress().equals(getSharedPreferences("monitor", 0).getString("owner", ""));
    }

    private BluetoothGattServerCallback newCallback(final int epoch) { return new BluetoothGattServerCallback() {
        @Override public void onServiceAdded(int status, BluetoothGattService service) {
            if(closing || epoch!=gattEpoch)return;
            if (closing) return;
            if (status != BluetoothGatt.GATT_SUCCESS) { state = "GATT service error " + status; event("service_error", state); closeBluetooth(); return; }
            if (service.getUuid().equals(BATTERY)) {
                BluetoothGattService custom = new BluetoothGattService(SERVICE, BluetoothGattService.SERVICE_TYPE_PRIMARY);
                custom.addCharacteristic(stats); custom.addCharacteristic(live); custom.addCharacteristic(hardware);
                if (!server.addService(custom)) { event("service_error", "custom service rejected"); closeBluetooth(); }
            } else if (service.getUuid().equals(SERVICE)) {
                BluetoothGattService controlService=new BluetoothGattService(CONTROL_SERVICE,BluetoothGattService.SERVICE_TYPE_PRIMARY);
                controlService.addCharacteristic(new BluetoothGattCharacteristic(CONTROL,
                    BluetoothGattCharacteristic.PROPERTY_READ|BluetoothGattCharacteristic.PROPERTY_WRITE,
                    BluetoothGattCharacteristic.PERMISSION_READ_ENCRYPTED_MITM|BluetoothGattCharacteristic.PERMISSION_WRITE_ENCRYPTED_MITM));
                if(!server.addService(controlService)) { event("service_error","control service rejected"); closeBluetooth(); }
            } else advertise();
        }
        @Override public void onConnectionStateChange(BluetoothDevice device, int status, int newState) {
            if(closing || epoch!=gattEpoch)return;
            if (newState == BluetoothProfile.STATE_CONNECTED) { devices.put(device.getAddress(), device); mtus.put(device.getAddress(), 23); }
            else {
                devices.remove(device.getAddress()); mtus.remove(device.getAddress());
                timeoutHandler.post(MonitorService.this::resetNotifications);
                subscriptions.removeIf(k -> k.startsWith(device.getAddress()));
                readSnapshots.keySet().removeIf(k -> k.startsWith(device.getAddress()));
            }
            connections = devices.size(); state = connections > 0 ? "Phone connected · encrypted reads require pairing" : "Bluetooth ready · scan for Thor";
            event("connection", "state=" + newState + ", status=" + status);
        }
        @Override public void onMtuChanged(BluetoothDevice device, int mtu) {
            if(closing || epoch!=gattEpoch)return; mtus.put(device.getAddress(), mtu); event("mtu", "negotiated=" + mtu); }
        @Override public void onCharacteristicReadRequest(BluetoothDevice d, int request, int offset, BluetoothGattCharacteristic c) {
            if(closing || epoch!=gattEpoch)return;
            if (!authorized(d)) { server.sendResponse(d, request, BluetoothGatt.GATT_INSUFFICIENT_AUTHENTICATION, offset, null); return; }
            String key = d.getAddress() + c.getUuid();
            if(offset==0){try{readSnapshots.put(key,c.getUuid().equals(CONTROL)?ControlPacket.bluetooth(controls.readSnapshot()):value(c.getUuid(),capture("ble_read")));}catch(Exception e){server.sendResponse(d,request,BluetoothGatt.GATT_FAILURE,offset,null);event("control_reply_error",e.getClass().getSimpleName());return;}}
            byte[] bytes = readSnapshots.get(key);
            if (bytes == null || offset < 0 || offset > bytes.length) { server.sendResponse(d, request, BluetoothGatt.GATT_INVALID_OFFSET, offset, null); return; }
            // The Bluetooth stack knows the connection's actual MTU and clips the ATT
            // response itself. A new GATT server on an existing connection may never
            // receive onMtuChanged: clipping to an assumed MTU here truncates JSON.
            byte[] response = Arrays.copyOfRange(bytes, offset, bytes.length);
            boolean sent = server.sendResponse(d, request, BluetoothGatt.GATT_SUCCESS, offset, response);
            event("read", "characteristic=" + c.getUuid() + ", offset=" + offset + ", bytes=" + response.length + ", sent=" + sent);
        }
        @Override public void onCharacteristicWriteRequest(BluetoothDevice d,int request,BluetoothGattCharacteristic c,boolean prepared,boolean response,int offset,byte[] bytes) {
            if(closing || epoch!=gattEpoch)return;
            int status=BluetoothGatt.GATT_SUCCESS;
            if(!authorized(d)) status=BluetoothGatt.GATT_INSUFFICIENT_AUTHENTICATION;
            else if(!c.getUuid().equals(CONTROL) || prepared || offset!=0 || bytes==null || bytes.length>180) status=BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED;
            else controls.apply(bytes); // Application result is returned by the correlated control read.
            if(closing || epoch!=gattEpoch || server==null){controls.clearShot();return;}
            if(response) server.sendResponse(d,request,status,offset,null);
            if(status==BluetoothGatt.GATT_SUCCESS && controls.takeStreamRequest())timeoutHandler.post(()->streamScreenshot(d));
        }
        @Override public void onDescriptorReadRequest(BluetoothDevice d, int request, int offset, BluetoothGattDescriptor desc) {
            if(closing || epoch!=gattEpoch)return;
            if (desc.getUuid().equals(CCC) && !authorized(d)) { server.sendResponse(d, request, BluetoothGatt.GATT_INSUFFICIENT_AUTHENTICATION, offset, null); return; }
            byte[] bytes = desc.getUuid().equals(CCC) ? (subscriptions.contains(d.getAddress() + desc.getCharacteristic().getUuid()) ? BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE : BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE) : desc.getValue();
            if (bytes == null || offset < 0 || offset > bytes.length) server.sendResponse(d, request, BluetoothGatt.GATT_INVALID_OFFSET, offset, null);
            else server.sendResponse(d, request, BluetoothGatt.GATT_SUCCESS, offset, Arrays.copyOfRange(bytes, offset, bytes.length));
        }
        @Override public void onDescriptorWriteRequest(BluetoothDevice d, int request, BluetoothGattDescriptor desc, boolean prepared, boolean response, int offset, byte[] bytes) {
            if(closing || epoch!=gattEpoch)return;
            int status = BluetoothGatt.GATT_SUCCESS;
            if (!authorized(d)) status = BluetoothGatt.GATT_INSUFFICIENT_AUTHENTICATION;
            else if (prepared || offset != 0 || !desc.getUuid().equals(CCC) || (!Arrays.equals(bytes, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE) && !Arrays.equals(bytes, BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE))) status = BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED;
            else {
                String key = d.getAddress() + desc.getCharacteristic().getUuid();
                if (Arrays.equals(bytes, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)) subscriptions.add(key); else subscriptions.remove(key);
                event("subscription", "characteristic=" + desc.getCharacteristic().getUuid() + ", enabled=" + subscriptions.contains(key));
            }
            if (response) server.sendResponse(d, request, status, offset, null);
        }
        @Override public void onNotificationSent(BluetoothDevice d, int status) {
            if(closing || epoch!=gattEpoch)return;
            timeoutHandler.post(()->{if(epoch==gattEpoch)notificationDelivered(status);}); }
    }; }

    private final BroadcastReceiver batteryReceiver=new BroadcastReceiver(){
        private int lastPlug=-1,lastLevel=-1,lastStatus=-1;
        public void onReceive(Context c,Intent i){
            int plug=i.getIntExtra(BatteryManager.EXTRA_PLUGGED,0),level=i.getIntExtra(BatteryManager.EXTRA_LEVEL,-1),status=i.getIntExtra(BatteryManager.EXTRA_STATUS,-1);
            if(plug!=lastPlug&&powerSaving!=null&&timer!=null)timer.execute(()->evaluatePower());
            if(plug!=lastPlug||level!=lastLevel||status!=lastStatus){lastPlug=plug;lastLevel=level;lastStatus=status;capture("battery_event");notifySubscribers();}
        }
    };
    private final BroadcastReceiver screenReceiver = new BroadcastReceiver() {
        @Override public void onReceive(Context c, Intent i) { if(PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED.equals(i.getAction()))BatteryHistory.get(c).sleepEvent(System.currentTimeMillis(),getSystemService(PowerManager.class).isDeviceIdleMode()?2:3);event("screen", i.getAction()); capture("screen");if(powerSaving!=null&&timer!=null)timer.execute(()->evaluatePower()); }
    };
    private final BroadcastReceiver bondReceiver = new BroadcastReceiver() {
        @Override public void onReceive(Context c, Intent i) { event("bond", "state=" + i.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, -1)); }
    };
    @Override public int onStartCommand(Intent i, int flags, int id) {
        if(i!=null&&"REST_EVALUATE".equals(i.getAction())){if(powerSaving!=null&&monitoringStarted){timer.execute(()->evaluatePower());return START_STICKY;}}
        if(i!=null && "STOP_FIND".equals(i.getAction())){FindThor.requestStop();if(monitoringStarted)return START_STICKY;i=null;}
        if (i != null && "STOP".equals(i.getAction())) {
            getSharedPreferences("monitor",0).edit().putBoolean("monitor_wanted",false).apply();stopSelf();return START_NOT_STICKY;
        }
        boolean timed=i!=null && i.getBooleanExtra("active_test",false);
        if(i==null && !getSharedPreferences("monitor",0).getBoolean("monitor_wanted",false)){stopSelf();return START_NOT_STICKY;}
        monitoringStarted=true;
        continuous=!timed && getSharedPreferences("monitor",0).getBoolean("always_on",true);
        getSharedPreferences("monitor",0).edit().putBoolean("monitor_wanted",!timed).putBoolean("always_on",continuous).apply();
        timeoutHandler.removeCallbacks(testTimeout);
        if (testWakeLock != null && testWakeLock.isHeld()) testWakeLock.release();
        activeUntil = 0;
        if (timed) {
            activeUntil = SystemClock.elapsedRealtime() + TEST_MS;
            testWakeLock.acquire(TEST_MS);
            timeoutHandler.postDelayed(testTimeout, TEST_MS);
            event("active_test_started", "CPU wake lock acquired with a 10-minute maximum; screens may sleep");
            getSystemService(NotificationManager.class).notify(1, notification("10-minute test · CPU awake, screens may sleep"));
            capture("active_test");
        } else if(continuous) {
            testWakeLock.acquire();
            event("continuous_mode","CPU stays awake while monitoring is enabled");
            getSystemService(NotificationManager.class).notify(1,notification("Monitoring · stays active with the lid closed"));
        } else {
            event("passive_mode", "No wake lock");
            getSystemService(NotificationManager.class).notify(1, notification("Passive monitoring · CPU may sleep"));
        }
        if(!timed)timer.execute(()->evaluatePower());
        Recovery.attempt(this);
        return timed?START_NOT_STICKY:START_STICKY;
    }
    @Override public void onTaskRemoved(Intent rootIntent){
        event("task_dismissed","Foreground monitoring continues independently of its activity");
        ServiceRecovery.schedule(this);super.onTaskRemoved(rootIntent);
    }
    @Override public void onConfigurationChanged(android.content.res.Configuration configuration){super.onConfigurationChanged(configuration);LocatorStopPanel.refresh(this);}
    @Override public void onDestroy() {
        closing = true;
        if(instance==this)instance=null;
        FindThor.stopNow();FileAccess.stop();ServiceRecovery.schedule(this);
        resetNotifications();
        running = false;
        timeoutHandler.removeCallbacks(testTimeout);
        if(powerSaving!=null&&!getSharedPreferences("monitor",0).getBoolean("monitor_wanted",false)){getSystemService(AlarmManager.class).cancel(PendingIntent.getBroadcast(this,74,new Intent(this,PowerSavingReceiver.class).setAction("com.alan.thormonitor.REST_ALARM"),PendingIntent.FLAG_UPDATE_CURRENT|PendingIntent.FLAG_IMMUTABLE));}
        if (testWakeLock != null && testWakeLock.isHeld()) { testWakeLock.release(); event("wake_lock_released", "Service stopped"); }
        activeUntil = 0;continuous=false;
        if (timer != null) timer.shutdownNow();
        try { if (advertiser != null) advertiser.stopAdvertising(currentAdvertisingCallback); } catch (Exception ignored) {}
        try { if (server != null) { for (BluetoothDevice d : devices.values()) server.cancelConnection(d); server.close(); } } catch (Exception ignored) {}
        try { unregisterReceiver(screenReceiver); unregisterReceiver(bondReceiver); unregisterReceiver(radioReceiver);unregisterReceiver(batteryReceiver); } catch (Exception ignored) {}
        try{getSystemService(android.net.ConnectivityManager.class).unregisterNetworkCallback(networkCallback);}catch(Exception ignored){}
        connections = 0;
        if (!state.contains("Error") && !state.contains("failed") && !state.contains("error")) state = "Monitoring stopped";
        event("stopped", state); super.onDestroy();
    }
    @Override public IBinder onBind(Intent i) { return null; }
}
