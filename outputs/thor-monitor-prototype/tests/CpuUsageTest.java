package com.alan.thormonitor;
public class CpuUsageTest {
    static void check(boolean value) { if (!value) throw new AssertionError(); }
    public static void main(String[] args) {
        CpuUsage cpu = new CpuUsage();
        check(cpu.sample("cpu 100 0 100 800 0 0 0 0 100 0", 0).percent == null);
        check(cpu.sample("cpu 100 0 100 800 0 0 0 0 100 0", 500).percent == null);
        CpuUsage.Reading r = cpu.sample("cpu 125 0 125 950 0 0 0 0 125 0", 2000);
        check(r.percent == 25.0 && r.windowMs == 2000);
        check(cpu.sample("cpu 125 0 125 1150 0 0 0 0 125 0", 4000).percent == 0.0);
        check(cpu.sample("cpu 225 0 225 1150 0 0 0 0 225 0", 6000).percent == 100.0);
        check(cpu.sample("cpu 225 0 225 1150 100 0 0 0", 8000).percent == 0.0);
        check(cpu.sample("cpu 1 0 1 1 0 0 0 0", 10000).percent == null);
        check(cpu.sample("unavailable", 12000).percent == null);
        check(cpu.sample("cpu -1 0 1 1 0 0 0 0", 14000).percent == null);
        System.out.println("CPU counter tests passed (idle, busy, I/O wait, guests, warmup, reset, unavailable).");
    }
}
