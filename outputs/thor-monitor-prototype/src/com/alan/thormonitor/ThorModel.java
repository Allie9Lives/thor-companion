package com.alan.thormonitor;

import java.util.Locale;

/** Hardware inference from AYN's published configurations, never from free space or SD cards. */
final class ThorModel {
    static String socFamily(String soc) {
        String s = soc == null ? "" : soc.toLowerCase(Locale.ROOT).replaceAll("[^a-z0-9]", "");
        if (s.equals("qcs8550") || s.equals("sm8550") || s.equals("snapdragon8gen2")) return "8gen2";
        if (s.equals("sm8250") || s.equals("snapdragon865")) return "865";
        return "unknown";
    }
    static boolean isThor(String model) {
        return model != null && model.toLowerCase(Locale.ROOT).replace('_', ' ').matches(".*\\bthor\\b.*");
    }
    static String variant(String model, String soc, long ram) {
        if (!isThor(model)) return null;
        double gib = ram / 1073741824.0; // Android reserves part of the installed RAM.
        String family = socFamily(soc);
        if (family.equals("865") && gib >= 6.5 && gib <= 8.5) return "Lite";
        if (!family.equals("8gen2")) return null;
        if (gib >= 6.5 && gib <= 8.5) return "Base";
        if (gib >= 10 && gib <= 12.5) return "Pro";
        if (gib >= 14 && gib <= 16.5) return "Max";
        return null; // Unknown/revised configurations must not be silently mislabeled.
    }
    static String cpuName(String model, String soc) {
        if (!isThor(model)) return null;
        String family = socFamily(soc);
        return family.equals("8gen2") ? "Qualcomm Snapdragon 8 Gen 2" :
            family.equals("865") ? "Qualcomm Snapdragon 865" : null;
    }
    static Long storageCapacity(long usableDataBytes) {
        for (long nominal : new long[]{128_000_000_000L, 256_000_000_000L, 512_000_000_000L, 1_000_000_000_000L}) {
            if (usableDataBytes >= nominal * 0.8 && usableDataBytes <= nominal * 1.05) return nominal;
        }
        return null;
    }
}
