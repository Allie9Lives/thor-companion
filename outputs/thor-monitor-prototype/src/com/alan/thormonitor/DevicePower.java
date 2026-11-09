package com.alan.thormonitor;
final class DevicePower {
    static String[] command(int value) {
        switch(value){
            case 0:return new String[]{"/system/bin/input","keyevent","223"};
            case 3:return new String[]{"/system/bin/input","keyevent","224"};
            case 1:return new String[]{"/system/bin/svc","power","reboot"};
            case 2:return new String[]{"/system/bin/svc","power","shutdown"};
            default:throw new IllegalArgumentException("Unsupported power action");
        }
    }
}
