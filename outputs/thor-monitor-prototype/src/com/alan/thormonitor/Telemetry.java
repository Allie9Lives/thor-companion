package com.alan.thormonitor;

import android.app.ActivityManager;
import android.content.*;
import android.os.*;
import android.provider.Settings;
import android.os.storage.StorageManager;
import android.os.storage.StorageVolume;
import org.json.JSONObject;
import java.io.*;
import java.nio.charset.StandardCharsets;

final class Telemetry {
    private final CpuUsage cpu = new CpuUsage();
    static String read(String path) {
        try (BufferedReader r = new BufferedReader(new FileReader(path))) { return r.readLine().trim(); }
        catch (Exception e) { return "unavailable"; }
    }

    JSONObject sample(Context c, long sequence) {
        JSONObject j = new JSONObject();
        try {
            Intent b = c.registerReceiver(null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
            BatteryManager bm = c.getSystemService(BatteryManager.class);
            ActivityManager.MemoryInfo mem = new ActivityManager.MemoryInfo();
            c.getSystemService(ActivityManager.class).getMemoryInfo(mem);
            StatFs fs = new StatFs(Environment.getDataDirectory().getPath());
            j.put("schema", 1).put("sequence", sequence).put("sampled_at_ms", System.currentTimeMillis());
            j.put("elapsed_realtime_ms", SystemClock.elapsedRealtime());
            j.put("model", Build.MODEL).put("manufacturer", Build.MANUFACTURER);
            String deviceName = null;
            try { deviceName = Settings.Global.getString(c.getContentResolver(), "device_name"); }
            catch (SecurityException ignored) {}
            j.put("device_name", deviceName == null || deviceName.trim().isEmpty() ? Build.MODEL : deviceName.trim());
            j.put("android", Build.VERSION.RELEASE).put("build", Build.DISPLAY);
            String soc = Build.SOC_MODEL;
            String maker = Build.SOC_MANUFACTURER;
            String variant = ThorModel.variant(Build.MODEL, soc, mem.totalMem);
            j.put("variant", variant == null ? JSONObject.NULL : variant);
            j.put("soc_model", soc);
            Long storageCapacity = ThorModel.storageCapacity(fs.getTotalBytes());
            j.put("storage_capacity_bytes", variant == null || storageCapacity == null ? JSONObject.NULL : storageCapacity);
            String cpuName = ThorModel.cpuName(Build.MODEL, soc);
            j.put("cpu_name", cpuName != null ? cpuName : soc == null || soc.equals(Build.UNKNOWN) ? JSONObject.NULL :
                (("QTI".equalsIgnoreCase(maker) ? "Qualcomm" : maker) + " " + soc).trim());
            String gpuModel = read("/sys/class/kgsl/kgsl-3d0/gpu_model");
            java.util.regex.Matcher gpuName = java.util.regex.Pattern.compile("(?i)Adreno\\s*([0-9]+)").matcher(gpuModel);
            j.put("gpu_name", gpuName.find() ? "Adreno " + gpuName.group(1) : JSONObject.NULL);
            j.put("ram_total_bytes", mem.totalMem).put("ram_available_bytes", mem.availMem);
            CpuUsage.Reading usage = cpu.sample(read("/proc/stat"), SystemClock.elapsedRealtime());
            j.put("cpu_percent", usage.percent == null ? JSONObject.NULL : usage.percent);
            j.put("cpu_window_ms", usage.windowMs);
            String gpu = read("/sys/class/kgsl/kgsl-3d0/gpu_busy_percentage");
            Object gpuPercent = JSONObject.NULL;
            try {
                double n = Double.parseDouble(gpu.replace("%", "").trim());
                if (Double.isFinite(n) && n >= 0 && n <= 100) gpuPercent = n;
            } catch (Exception ignored) {}
            j.put("gpu_percent", gpuPercent);
            j.put("data_total_bytes", fs.getTotalBytes()).put("data_available_bytes", fs.getAvailableBytes());
            sdCard(c, j);
            if (b != null) {
                int level = b.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
                int scale = b.getIntExtra(BatteryManager.EXTRA_SCALE, -1);
                j.put("battery_percent", level >= 0 && scale > 0 ? (100.0 * level / scale) : JSONObject.NULL);
                int temperature = b.getIntExtra(BatteryManager.EXTRA_TEMPERATURE, Integer.MIN_VALUE);
                j.put("battery_temperature_c", temperature == Integer.MIN_VALUE ? JSONObject.NULL : temperature / 10.0);
                int voltage = b.getIntExtra(BatteryManager.EXTRA_VOLTAGE, -1);
                j.put("battery_voltage_mv", voltage < 0 ? JSONObject.NULL : voltage);
                j.put("battery_health_code", b.getIntExtra(BatteryManager.EXTRA_HEALTH, BatteryManager.BATTERY_HEALTH_UNKNOWN));
                j.put("battery_status_code", b.getIntExtra(BatteryManager.EXTRA_STATUS, -1));
                j.put("plugged_code", b.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0));
            }
            property(j, "current_ua_raw", bm, BatteryManager.BATTERY_PROPERTY_CURRENT_NOW);
            property(j, "charge_counter_uah", bm, BatteryManager.BATTERY_PROPERTY_CHARGE_COUNTER);
            Object inputWatts = JSONObject.NULL;
            if (b != null && b.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) != 0) {
                try {
                    long uv = Long.parseLong(read("/sys/class/power_supply/usb/voltage_now"));
                    long ua = Long.parseLong(read("/sys/class/power_supply/usb/current_now"));
                    if (uv >= 1_000_000 && uv <= 48_000_000 && ua >= 0 && ua <= 10_000_000)
                        inputWatts = Math.round((uv / 1_000_000.0) * (ua / 1_000_000.0) * 100) / 100.0;
                } catch (Exception ignored) {}
            }
            j.put("input_watts", inputWatts);
            for(String[] entry:new String[][]{{"full_charge_uah","charge_full"},{"design_charge_uah","charge_full_design"},{"cycle_count","cycle_count"}}){
                Object value=JSONObject.NULL;
                try{long n=Long.parseLong(read("/sys/class/power_supply/battery/"+entry[1]));if(n>=0 && n<=(entry[1].equals("cycle_count")?100000:20000000))value=n;}catch(Exception ignored){}
                j.put(entry[0],value);
            }
            j.put("interactive", c.getSystemService(PowerManager.class).isInteractive());
            j.put("device_idle", c.getSystemService(PowerManager.class).isDeviceIdleMode());
            j.put("storage_model", read("/sys/block/sda/device/model"));
            String v = read("/sys/devices/platform/soc/1d84000.ufshc/device_descriptor/specification_version");
            j.put("ufs_descriptor", v);
            j.put("ufs_version", v.equals("0x0400") ? "4.0" : v.equals("0x0310") ? "3.1" : "unknown");
        } catch (Exception e) { try { j.put("error", e.toString()); } catch (Exception ignored) {} }
        return j;
    }

    // StorageVolume also includes USB disks. Match its mounted block device to
    // an SD device in sysfs rather than treating every removable disk as microSD.
    static boolean isSdVolume(StorageVolume volume) {
        String uuid = volume.getUuid();
        if (uuid == null) return false;
        try (BufferedReader r = new BufferedReader(new FileReader("/proc/mounts"))) {
            String line;
            while ((line = r.readLine()) != null) {
                String[] fields = line.split(" ");
                if (fields.length < 2 || !fields[1].equals("/mnt/media_rw/" + uuid)) continue;
                String source = fields[0];
                int index = source.lastIndexOf("public:");
                if (index < 0) continue;
                String numbers = source.substring(index + 7).replace(',', ':');
                if (!numbers.matches("[0-9]+:[0-9]+")) continue;
                File device = new File("/sys/dev/block/" + numbers).getCanonicalFile();
                for (int n = 0; device != null && n < 5; n++, device = device.getParentFile())
                    if (read(new File(device, "device/type").getPath()).equals("SD")) return true;
            }
        } catch (Exception ignored) {}
        return false;
    }

    private static boolean hasSdDevice() {
        File[] blocks = new File("/sys/class/block").listFiles();
        if (blocks != null) for (File block : blocks)
            if (block.getName().matches("mmcblk[0-9]+") && read(new File(block, "device/type").getPath()).equals("SD")) return true;
        return false;
    }

    private static void sdCard(Context c, JSONObject j) throws Exception {
        j.put("sd_state", "not_present").put("sd_total_bytes", JSONObject.NULL).put("sd_available_bytes", JSONObject.NULL);
        try {
            StorageManager storage = c.getSystemService(StorageManager.class);
            boolean removable = false;
            for (StorageVolume volume : storage.getStorageVolumes()) {
                if (volume.isPrimary() || !volume.isRemovable()) continue;
                removable = true;
                if (!isSdVolume(volume)) continue;
                String state = volume.getState();
                if (!Environment.MEDIA_MOUNTED.equals(state) && !Environment.MEDIA_MOUNTED_READ_ONLY.equals(state)) {
                    j.put("sd_state", "not_mounted"); return;
                }
                j.put("sd_state", Environment.MEDIA_MOUNTED_READ_ONLY.equals(state) ? "read_only" : "mounted");
                File directory = volume.getDirectory();
                if (directory == null) { j.put("sd_state", "unavailable"); return; }
                try {
                    StatFs fs = new StatFs(directory.getPath());
                    long total = fs.getTotalBytes(), available = fs.getAvailableBytes();
                    if (total <= 0 || available < 0 || available > total) throw new IllegalStateException();
                    j.put("sd_total_bytes", total).put("sd_available_bytes", available);
                } catch (Exception e) { j.put("sd_state", "unavailable"); }
                return;
            }
            if (hasSdDevice()) j.put("sd_state", "not_mounted");
            else if (removable) j.put("sd_state", "unavailable");
        } catch (Exception e) { j.put("sd_state", "unavailable"); }
    }

    private static void property(JSONObject j, String key, BatteryManager bm, int id) throws Exception {
        long value = bm.getLongProperty(id);
        j.put(key, value == Long.MIN_VALUE ? JSONObject.NULL : value);
    }

    static synchronized void log(Context c, String event, JSONObject data) {
        try {
            File file = new File(c.getFilesDir(), "diagnostics.jsonl");
            if (file.length() > 512 * 1024) {
                File previous = new File(c.getFilesDir(), "diagnostics.previous.jsonl");
                if (previous.exists()) previous.delete();
                file.renameTo(previous);
            }
            JSONObject j = new JSONObject().put("at_ms", System.currentTimeMillis()).put("event", event);
            if (data != null) j.put("data", data);
            try (FileOutputStream out = new FileOutputStream(file, true)) {
                out.write((j.toString() + "\n").getBytes(StandardCharsets.UTF_8));
            }
        } catch (Exception ignored) {}
    }
}
