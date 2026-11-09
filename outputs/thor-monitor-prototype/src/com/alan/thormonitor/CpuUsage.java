package com.alan.thormonitor;

/** Aggregate busy time across all cores, excluding idle and I/O wait. */
final class CpuUsage {
    private long total = -1, idle, at;
    private Reading last = new Reading(null, 0);
    static final class Reading {
        final Double percent;
        final long windowMs;
        Reading(Double percent, long windowMs) { this.percent = percent; this.windowMs = windowMs; }
    }

    synchronized Reading sample(String line, long now) {
        try {
            String[] fields = line.trim().split("\\s+");
            if (!fields[0].equals("cpu") || fields.length < 9) throw new IllegalArgumentException();
            long nextTotal = 0;
            // guest/guest_nice are already included in user/nice; do not add twice.
            for (int i = 1; i <= 8; i++) {
                long ticks = Long.parseLong(fields[i]);
                if (ticks < 0) throw new IllegalArgumentException();
                nextTotal = Math.addExact(nextTotal, ticks);
            }
            long nextIdle = Math.addExact(Long.parseLong(fields[4]), Long.parseLong(fields[5]));
            if (total < 0 || now < at || nextTotal < total || nextIdle < idle) {
                total = nextTotal; idle = nextIdle; at = now;
                return last = new Reading(null, 0);
            }
            long window = now - at;
            if (window < 1000) return last;
            long elapsed = nextTotal - total, inactive = nextIdle - idle;
            total = nextTotal; idle = nextIdle; at = now;
            if (elapsed <= 0 || inactive > elapsed) return last = new Reading(null, 0);
            double percentage = 100.0 * (elapsed - inactive) / elapsed;
            return last = new Reading(Math.round(percentage * 10) / 10.0, window);
        } catch (Exception e) {
            total = -1;
            return last = new Reading(null, 0);
        }
    }
}
