package com.alan.thormonitor;
import android.os.*;import org.json.*;import java.lang.reflect.*;
public class WifiPacketProbe {
 public static void main(String[] args)throws Exception{
  Looper.prepareMainLooper();JSONObject j=new JSONObject().put("wifi_event",65535).put("keep_alive_paused",false).put("locator_active",false).put("full_charge_uah",20000000).put("design_charge_uah",20000000).put("cycle_count",100000).put("battery_health_code",7).put("sequence",Integer.MAX_VALUE).put("sampled_at_ms",System.currentTimeMillis()).put("battery_percent",100).put("battery_temperature_c",150).put("battery_voltage_mv",48000).put("current_ua_raw",-10000000).put("charge_counter_uah",20000000).put("battery_status_code",5).put("plugged_code",4).put("interactive",false).put("device_idle",false).put("data_available_bytes",1000000000000L).put("cpu_percent",100).put("cpu_window_ms",604800000).put("gpu_percent",100).put("ram_available_bytes",16000000000L).put("sd_state","unavailable").put("sd_total_bytes",2000000000000L).put("sd_available_bytes",2000000000000L).put("input_watts",480);
  Method value=MonitorService.class.getDeclaredMethod("value",java.util.UUID.class,JSONObject.class);value.setAccessible(true);byte[] bytes=(byte[])value.invoke(new MonitorService(),MonitorService.STATS,j);JSONObject decoded=new JSONObject(new String(bytes,"UTF-8"));if(bytes.length>512)throw new AssertionError("Telemetry exceeds ATT limit: "+bytes.length);
  for(String key:new String[]{"we","battery_pct","cpu_pct","gpu_pct","ram_free_bytes","sd_total_bytes","free_bytes","keep_alive_paused","locator_active"})if(!decoded.has(key))throw new AssertionError("Core field missing: "+key);
  System.out.println("PASS: worst-case telemetry "+bytes.length+" bytes; core readings and Wi-Fi event retained.");
 }
}
