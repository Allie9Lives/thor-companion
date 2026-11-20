package com.alan.thormonitor;

import java.util.Locale;

/** Hardware inference from published configurations, never from free space or SD cards. */
final class ThorModel {
    /** Vendor controls (fan, LED, performance…) are only written on AYN firmware; other makers reuse setting names with other meanings. */
    static String family(String maker, String model) {
        String m = maker == null ? "" : maker.toLowerCase(Locale.ROOT), n = model == null ? "" : model.toLowerCase(Locale.ROOT);
        if (m.equals("ayn") || isThor(model) || odinLine(model) != null) return "ayn";
        if (n.startsWith("retroid")) return "retroid";
        return "android";
    }
    /** Retail name for recognized handhelds; everything else is a generic handheld. */
    static String product(String maker, String model) {
        if (isThor(model)) return "AYN Thor";
        String odin = odinLine(model);
        if (odin != null) return "AYN " + odin;
        if (isRetroidClassic(model)) return "Retroid Pocket Classic";
        return "Handheld Device";
    }
    /** "Find my …" label: Thor, Retroid or handheld. */
    static String findLabel(String model) {
        return "Find my " + (isThor(model) ? "Thor" : odinLine(model) != null ? "Odin" : isRetroidClassic(model) ? "Retroid" : "handheld");
    }
    static String findLabel() { return findLabel(android.os.Build.MODEL); }
    static String socFamily(String soc) {
        String s = soc == null ? "" : soc.toLowerCase(Locale.ROOT).replaceAll("[^a-z0-9]", "");
        if (s.equals("qcs8550") || s.equals("sm8550") || s.equals("snapdragon8gen2")) return "8gen2";
        if (s.equals("sm8250") || s.equals("snapdragon865")) return "865";
        if (s.equals("sm8750") || s.equals("snapdragon8elite") || s.equals("dragonwingq8")) return "8elite";
        if (s.equals("sdm845") || s.equals("snapdragon845")) return "845";
        if (s.equals("mt6877") || s.equals("dimensity900")) return "d900";
        if (s.startsWith("mt6883") || s.startsWith("mt6885") || s.startsWith("dimensity1000")) return "d1000";
        return "unknown";
    }
    static boolean isThor(String model) {
        return model != null && model.toLowerCase(Locale.ROOT).replace('_', ' ').matches(".*\\bthor\\b.*");
    }
    static String variant(String model, String soc, long ram) {
        double gib = ram / 1073741824.0; // Android reserves part of the installed RAM.
        if (isRetroidClassic(model)) return gib >= 3 && gib <= 4.2 ? "4 GB" : gib >= 4.8 && gib <= 6.3 ? "6 GB" : null;
        String odin = odinLine(model), f = socFamily(soc);
        if (odin != null) {
            // Published tiers: Odin 3 Base/Pro/Max/Ultra (8/12/16/24 GB), Odin 2 (+Mini, Portal) Base/Pro/Max (8/12/16 GB),
            // Odin Base/Pro (4/8 GB, Snapdragon 845) and Odin Lite (4 GB, MediaTek Dimensity).
            if (odin.equals("Odin")) return f.equals("d900") || f.equals("d1000") ? "Lite" : !f.equals("845") ? null :
                gib >= 3 && gib <= 4.2 ? "Base" : gib >= 6.5 && gib <= 8.5 ? "Pro" : null;
            if (!f.equals(odin.equals("Odin 3") ? "8elite" : "8gen2")) return null;
            if (odin.equals("Odin 3") && gib >= 21 && gib <= 24.5) return "Ultra";
            return tier(gib);
        }
        if (!isThor(model)) return null;
        String family = socFamily(soc);
        if (family.equals("865") && gib >= 6.5 && gib <= 8.5) return "Lite";
        if (!family.equals("8gen2")) return null;
        return tier(gib);
    }
    /** 8/12/16 GB → Base/Pro/Max; unknown or revised configurations must not be silently mislabeled. */
    private static String tier(double gib) {
        if (gib >= 6.5 && gib <= 8.5) return "Base";
        if (gib >= 10 && gib <= 12.5) return "Pro";
        if (gib >= 14 && gib <= 16.5) return "Max";
        return null;
    }
    /** "Odin 3", "Odin 2 Portal", "Odin 2 Mini", "Odin 2", "Odin" (original/Lite), or null. Accepts "Odin2", "AYN_Odin2_Mini"… */
    static String odinLine(String model) {
        if (model == null) return null;
        String n = model.toLowerCase(Locale.ROOT).replaceAll("[_\\-]", " ");
        java.util.regex.Matcher m = java.util.regex.Pattern.compile("\\bodin ?([23])?\\b").matcher(n);
        if (!m.find()) return null;
        if (m.group(1) == null) return "Odin";
        String line = "Odin " + m.group(1);
        return line.equals("Odin 2") && n.contains("portal") ? "Odin 2 Portal" : line.equals("Odin 2") && n.contains("mini") ? "Odin 2 Mini" : line;
    }
    static boolean isRetroidClassic(String model) {
        return model != null && model.toLowerCase(Locale.ROOT).replace('_', ' ').equals("retroid pocket classic");
    }
    static String cpuName(String model, String soc) {
        if (isRetroidClassic(model)) return "Qualcomm Snapdragon G1 Gen 2";
        String family = socFamily(soc);
        if (odinLine(model) != null) return family.equals("8elite") ? "Qualcomm Snapdragon 8 Elite" :
            family.equals("8gen2") ? "Qualcomm Snapdragon 8 Gen 2" : family.equals("845") ? "Qualcomm Snapdragon 845" :
            family.equals("d900") ? "MediaTek Dimensity 900" : family.equals("d1000") ? "MediaTek Dimensity 1000" : null;
        if (!isThor(model)) return null;
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
