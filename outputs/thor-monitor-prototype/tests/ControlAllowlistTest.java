package com.alan.thormonitor;
public final class ControlAllowlistTest {
    private static void equal(String a,String b) { if(!a.equals(b)) throw new AssertionError(a+" != "+b); }
    private static void reject(String command,int value) {
        try { ControlHelper.setting(command,value); throw new AssertionError("Accepted "+command+" "+value); }
        catch(IllegalArgumentException expected) {}
    }
    public static void main(String[] args) {
        equal(ControlHelper.setting("hz",120),"peak_refresh_rate");
        equal(ControlHelper.setting("fan",4),"fan_mode");
        equal(ControlHelper.setting("volume",15),"secondary_screen_volume_level");
        equal(ControlHelper.setting("bypass",1),"is_charging_separation");
        reject("fan",3);reject("hz",90);reject("hz",144);reject("volume",16);
        reject("bypass",2);reject("performance",3);reject("focus",-1);
        reject("adb_enabled",1);reject("../../arbitrary",1);reject("volume;reboot",1);
        System.out.println("Control allowlist passed");
    }
}
