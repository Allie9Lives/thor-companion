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
        eq(ThorModel.family("Moorechip","Retroid Pocket Classic"),"retroid");eq(ThorModel.family("AYN","AYN Thor"),"ayn");eq(ThorModel.family("Google","Pixel 8"),"android");
        eq(ThorModel.product("Moorechip","Retroid Pocket Classic"),"Retroid Pocket Classic");eq(ThorModel.product("AYN","AYN_Thor"),"AYN Thor");eq(ThorModel.product("ANBERNIC","RG556"),"Handheld Device");eq(ThorModel.product("Google","Pixel 8"),"Handheld Device");eq(ThorModel.findLabel("AYN_Thor"),"Find my Thor");eq(ThorModel.findLabel("Retroid Pocket Classic"),"Find my Retroid");eq(ThorModel.findLabel("RG556"),"Find my handheld");
        eq(ThorModel.variant("Retroid Pocket Classic","SG4250P",5634136L*1024),"6 GB");eq(ThorModel.variant("Retroid Pocket Classic","SG4250P",3_800_000_000L),"4 GB");eq(ThorModel.cpuName("Retroid Pocket Classic","SG4250P"),"Qualcomm Snapdragon G1 Gen 2");
        if(ThorModel.variant("Pixel 8","x",8L<<30)!=null)throw new AssertionError("Generic device got a variant");
        eq(Telemetry.storageStandardFor("0x0400",null,null),"UFS 4.0");eq(Telemetry.storageStandardFor("unavailable","MMC","0x8"),"eMMC 5.1");eq(Telemetry.storageStandardFor(null,"MMC","0x5"),"eMMC");eq(Telemetry.storageStandardFor(null,"SD","0x8"),null);
        eq(ThorModel.product("AYN","Odin2"),"AYN Odin 2");eq(ThorModel.product("AYN","AYN_Odin2_Mini"),"AYN Odin 2 Mini");eq(ThorModel.product("AYN","Odin2 Portal"),"AYN Odin 2 Portal");eq(ThorModel.product("AYN","Odin3"),"AYN Odin 3");eq(ThorModel.product("AYN","Odin"),"AYN Odin");eq(ThorModel.family("x","Odin2"),"ayn");eq(ThorModel.findLabel("Odin3"),"Find my Odin");eq(ThorModel.product("x","Odinson"),"Handheld Device");
        eq(ThorModel.variant("Odin3","SM8750",23_000_000_000L),"Ultra");eq(ThorModel.variant("Odin3","SM8750",15_900_000_000L),"Max");eq(ThorModel.variant("Odin3","SM8550",15_900_000_000L),null);eq(ThorModel.variant("Odin2","SM8550",11_800_000_000L),"Pro");eq(ThorModel.variant("Odin2 Portal","QCS8550",7_800_000_000L),"Base");eq(ThorModel.variant("Odin2","SM8550",23_000_000_000L),null);
        eq(ThorModel.variant("Odin","SDM845",3_800_000_000L),"Base");eq(ThorModel.variant("Odin","SDM845",7_800_000_000L),"Pro");eq(ThorModel.variant("Odin","MT6877",3_800_000_000L),"Lite");eq(ThorModel.cpuName("Odin3","SM8750"),"Qualcomm Snapdragon 8 Elite");eq(ThorModel.cpuName("Odin","MT6877"),"MediaTek Dimensity 900");
        System.out.println("Thor model tests passed (all tiers, firmware alias, reserved RAM, unknown hardware, capacity).");
    }
}
