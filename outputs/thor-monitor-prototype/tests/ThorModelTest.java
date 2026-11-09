package com.alan.thormonitor;
public class ThorModelTest {
    static void eq(Object actual, Object expected) {
        if (!java.util.Objects.equals(actual, expected)) throw new AssertionError(actual + " != " + expected);
    }
    public static void main(String[] args) {
        eq(ThorModel.variant("AYN_Thor", "SM8250", 7_800_000_000L), "Lite");
        eq(ThorModel.variant("AYN Thor", "SM8550", 7_800_000_000L), "Base");
        eq(ThorModel.variant("AYN_Thor", "Snapdragon 8 Gen 2", 11_800_000_000L), "Pro");
        eq(ThorModel.variant("AYN_Thor", "QCS8550", 15_996_096_512L), "Max");
        eq(ThorModel.cpuName("AYN_Thor", "QCS8550"), "Qualcomm Snapdragon 8 Gen 2");
        eq(ThorModel.variant("Other handheld", "QCS8550", 15_996_096_512L), null);
        eq(ThorModel.variant("AYN_Thor", "unknown", 15_996_096_512L), null);
        eq(ThorModel.variant("AYN_Thor", "SM8250", 15_996_096_512L), null);
        eq(ThorModel.variant("AYN_Thor", "QCS8550", 4_000_000_000L), null);
        eq(ThorModel.storageCapacity(1_011_194_642_432L), 1_000_000_000_000L);
        eq(ThorModel.storageCapacity(495_000_000_000L), 512_000_000_000L);
        eq(ThorModel.storageCapacity(240_000_000_000L), 256_000_000_000L);
        eq(ThorModel.storageCapacity(112_000_000_000L), 128_000_000_000L);
        eq(ThorModel.storageCapacity(0), null);
        System.out.println("Thor model tests passed (all tiers, firmware alias, reserved RAM, unknown hardware, capacity).");
    }
}
