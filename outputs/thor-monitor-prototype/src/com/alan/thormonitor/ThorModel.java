package com.alan.thormonitor;

import java.util.Locale;

/** Hardware inference from published configurations, never from free space or SD cards. */
final class ThorModel {
    /** Vendor controls (fan, LED, performance…) are only written on AYN firmware; other makers reuse setting names with other meanings. */
    static String family(String maker, String model) {
        String m = maker == null ? "" : maker.toLowerCase(Locale.ROOT), n = model == null ? "" : model.toLowerCase(Locale.ROOT);
        if (m.equals("ayn") || isThor(model) || n.matches(".*\\bodin\\b.*")) return "ayn";
        if (n.startsWith("retroid")) return "retroid";
        return "android";
    }
    /** Retail name for recognized handhelds; everything else is a generic handheld. */
    static String product(String maker, String model) {
        if (isThor(model)) return "AYN Thor";
        if (isRetroidClassic(model)) return "Retroid Pocket Classic";
        return "Handheld Device";
    }
    /** "Find my …" label: Thor, Retroid or handheld. */
    static String findLabel(String model) {
        return "Find my " + (isThor(model) ? "Thor" : isRetroidClassic(model) ? "Retroid" : "handheld");
    }
    static String findLabel() { return findLabel(android.os.Build.MODEL); }
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
        double gib = ram / 1073741824.0; // Android reserves part of the installed RAM.
        if (isRetroidClassic(model)) return gib >= 3 && gib <= 4.2 ? "4 GB" : gib >= 4.8 && gib <= 6.3 ? "6 GB" : null;
        if (!isThor(model)) return null;
        String family = socFamily(soc);
        if (family.equals("865") && gib >= 6.5 && gib <= 8.5) return "Lite";
        if (!family.equals("8gen2")) return null;
        if (gib >= 6.5 && gib <= 8.5) return "Base";
        if (gib >= 10 && gib <= 12.5) return "Pro";
        if (gib >= 14 && gib <= 16.5) return "Max";
        return null; // Unknown/revised configurations must not be silently mislabeled.
    }
    static boolean isRetroidClassic(String model) {
        return model != null && model.toLowerCase(Locale.ROOT).replace('_', ' ').equals("retroid pocket classic");
    }
    static String cpuName(String model, String soc) {
        if (isRetroidClassic(model)) return "Qualcomm Snapdragon G1 Gen 2";
        if (!isThor(model)) return null;
        String family = socFamily(soc);
        return family.equals("8gen2") ? "Qualcomm Snapdragon 8 Gen 2" :
            family.equals("865") ? "Qualcomm Snapdragon 865" : null;
    }
    static Long storageCapacity(long usableDataBytes) {
        for (long nominal : new long[]{64_000_000_000L, 128_000_000_000L, 256_000_000_000L, 512_000_000_000L, 1_000_000_000_000L}) {
            if (usableDataBytes >= nominal * 0.8 && usableDataBytes <= nominal * 1.05) return nominal;
        }
        return null;
    }
}
