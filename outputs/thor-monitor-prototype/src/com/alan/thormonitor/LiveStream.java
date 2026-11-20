package com.alan.thormonitor;

import android.content.Context;
import android.net.LocalSocket;
import android.net.LocalSocketAddress;
import android.os.PowerManager;
import android.os.SystemClock;
import android.system.Os;
import android.system.OsConstants;
import android.system.StructTimeval;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import org.json.JSONObject;

/** Live H.264 view of one Thor screen: the shell helper runs screenrecord, the app relays it to the paired companion. */
final class LiveStream {
    static final int MAX_STREAMS = 2;
    static final long MAX_MS = 30 * 60000L;
    private static final AtomicInteger helperStreams = new AtomicInteger();
    // The stream per screen that a new request for that screen replaces (a phone restarting live view).
    private static final Runnable[] owners = new Runnable[2];

    // ---- Helper side (shell UID 2000) ----

    /** Writes 1 then the raw Annex-B stream, or 0 when it cannot start. screenrecord stops at 180 s, so it is restarted. */
    static void serve(JSONObject j, LocalSocket socket) throws Exception {
        int screen = integer(j, "value", 0, 1), quality = integer(j, "quality", 0, 1);
        FileDescriptor fd = Os.dup(socket.getFileDescriptor()); // the accept loop closes its own socket
        Os.setsockoptTimeval(fd, OsConstants.SOL_SOCKET, OsConstants.SO_SNDTIMEO, StructTimeval.fromMillis(0));
        Os.setsockoptTimeval(fd, OsConstants.SOL_SOCKET, OsConstants.SO_RCVTIMEO, StructTimeval.fromMillis(0));
        FileOutputStream out = new FileOutputStream(fd);
        final java.lang.Process[] current = new java.lang.Process[1];
        final boolean[] closed = new boolean[1];
        final AtomicBoolean released = new AtomicBoolean();
        final Runnable release = () -> { if (released.compareAndSet(false, true)) helperStreams.decrementAndGet(); };
        // Stops this stream at once and frees its slot; its threads finish in the background.
        final Runnable replace = () -> {
            synchronized (current) { closed[0] = true; if (current[0] != null) current[0].destroy(); }
            try { Os.shutdown(fd, OsConstants.SHUT_RDWR); } catch (Exception ignored) {}
            release.run();
        };
        Runnable previous;
        synchronized (owners) { previous = owners[screen]; owners[screen] = replace; }
        if (previous != null) previous.run();
        String[] g;
        try {
            if (helperStreams.incrementAndGet() > MAX_STREAMS) throw new IllegalStateException("busy");
            g = ScreenRecording.geometry(screen, quality);
        } catch (Exception e) {
            release.run();
            synchronized (owners) { if (owners[screen] == replace) owners[screen] = null; }
            try { out.write(0); } finally { out.close(); }
            return;
        }
        out.write(1);
        // A still screen sends nothing, so watch for the app hanging up instead of waiting for a failed write.
        Thread watch = new Thread(() -> {
            try {
                byte[] ignored = new byte[16];
                while (Os.read(fd, ignored, 0, ignored.length) > 0) { }
            } catch (Exception gone) {
                // Closed by either side.
            }
            synchronized (current) {
                closed[0] = true;
                if (current[0] != null) current[0].destroy();
            }
        }, "ThorLiveWatch");
        watch.setDaemon(true);
        watch.start();
        // Keepalive: an H.264 filler NAL (type 12, ignored by decoders) after 2 s without frames, so a phone
        // that left is noticed by the failed relay instead of holding a slot until screenrecord restarts.
        final Object writeLock = new Object();
        final long[] lastWrite = {SystemClock.elapsedRealtime()};
        Thread keepalive = new Thread(() -> {
            byte[] filler = {0, 0, 0, 1, 0x0C, (byte) 0xFF, (byte) 0x80};
            try {
                while (true) {
                    Thread.sleep(1000);
                    synchronized (current) { if (closed[0]) break; }
                    synchronized (writeLock) {
                        if (SystemClock.elapsedRealtime() - lastWrite[0] < 2000) continue;
                        out.write(filler);
                        lastWrite[0] = SystemClock.elapsedRealtime();
                    }
                }
            } catch (Exception gone) {
                synchronized (current) { closed[0] = true; if (current[0] != null) current[0].destroy(); }
            }
        }, "ThorLiveKeepalive");
        keepalive.setDaemon(true);
        keepalive.start();
        Thread t = new Thread(() -> {
            long end = SystemClock.elapsedRealtime() + MAX_MS;
            java.lang.Process p = null;
            try {
                while (SystemClock.elapsedRealtime() < end) {
                    long started = SystemClock.elapsedRealtime(), sent = 0;
                    synchronized (current) {
                        if (closed[0]) break;
                        p = new ProcessBuilder("/system/bin/screenrecord", "--output-format=h264", "--display-id", g[0], "--size", g[1],
                                "--bit-rate", quality == 1 ? "8000000" : "4000000", "--time-limit", "180", "-")
                                .redirectError(new File("/dev/null")).start();
                        current[0] = p;
                    }
                    try (InputStream in = p.getInputStream()) {
                        byte[] buffer = new byte[65536];
                        for (int n; (n = in.read(buffer)) != -1; ) {
                            synchronized (writeLock) { out.write(buffer, 0, n); lastWrite[0] = SystemClock.elapsedRealtime(); }
                            sent += n;
                        }
                    }
                    p.waitFor();
                    // A recorder that fails at once (screen off, display gone) must not spin.
                    if (sent == 0 && SystemClock.elapsedRealtime() - started < 2000) break;
                }
            } catch (Exception ignored) {
                // The companion closed the stream.
            } finally {
                if (p != null) p.destroy();
                try { Os.shutdown(fd, OsConstants.SHUT_RDWR); } catch (Exception ignored) {} // wakes the watcher
                try { out.close(); } catch (IOException ignored) {}
                release.run();
                synchronized (owners) { if (owners[screen] == replace) owners[screen] = null; }
            }
        }, "ThorLiveStream");
        t.setDaemon(true);
        t.start();
    }

    /** input: value 0 tap, 1 swipe, 2 back, 3 home; d screen; x,y,x2,y2 in 0..10000; ms 50..3000. */
    static String[] inputCommand(JSONObject j, int[] display) throws Exception {
        int action = integer(j, "value", 0, 3);
        String id = String.valueOf(display[0]);
        if (action == 2) return new String[]{"/system/bin/input", "-d", id, "keyevent", "4"};
        if (action == 3) return new String[]{"/system/bin/input", "-d", id, "keyevent", "3"};
        String x = scale(integer(j, "x", 0, 10000), display[1]), y = scale(integer(j, "y", 0, 10000), display[2]);
        if (action == 0) return new String[]{"/system/bin/input", "-d", id, "tap", x, y};
        return new String[]{"/system/bin/input", "-d", id, "swipe", x, y,
                scale(integer(j, "x2", 0, 10000), display[1]), scale(integer(j, "y2", 0, 10000), display[2]),
                String.valueOf(integer(j, "ms", 50, 3000))};
    }

    // ---- Virtual controller (helper side) ----

    /** Buttons the overlay may press; matches the Odin Controller key layout. */
    static final int[] PAD_KEYS = {96, 97, 99, 100, 102, 103, 104, 105, 106, 107, 108, 109, 110};
    // A, B, X, Y, L1, R1, L2, R2, THUMBL, THUMBR, START, SELECT, MODE
    private static final int[] AXES = {0, 1, 11, 14, 22, 23, 15, 16}; // X, Y, Z, RZ, GAS, BRAKE, HAT_X, HAT_Y
    private static final String[] AXIS_KEYS = {"x", "y", "z", "rz", "r", "l", "hx", "hy"};
    private static final float[] axisState = new float[AXES.length];
    private static long padDown;

    /** {"t":"b","k":keycode,"d":1|0} presses or releases; {"t":"a",...} sets absolute axes (sticks ±1000, triggers 0..1000, hats ±1). */
    static synchronized void pad(JSONObject j) throws Exception {
        long now = SystemClock.uptimeMillis();
        int device = gamepadDevice();
        String type = j.getString("t");
        if (type.equals("b")) {
            int key = integer(j, "k", 0, 300);
            boolean known = false;
            for (int k : PAD_KEYS) known |= k == key;
            if (!known) throw new IllegalArgumentException("Unknown button");
            boolean down = integer(j, "d", 0, 1) == 1;
            if (down) padDown = now;
            inject(new android.view.KeyEvent(padDown, now, down ? android.view.KeyEvent.ACTION_DOWN : android.view.KeyEvent.ACTION_UP,
                    key, 0, 0, device, 0, 0, android.view.InputDevice.SOURCE_GAMEPAD));
            return;
        }
        if (!type.equals("a")) throw new IllegalArgumentException("Unknown event");
        for (int i = 0; i < AXES.length; i++) {
            if (!j.has(AXIS_KEYS[i])) continue;
            boolean hat = i >= 6, trigger = i == 4 || i == 5;
            int v = hat ? integer(j, AXIS_KEYS[i], -1, 1) : integer(j, AXIS_KEYS[i], trigger ? 0 : -1000, 1000);
            axisState[i] = hat ? v : v / 1000f;
        }
        android.view.MotionEvent.PointerProperties[] props = {new android.view.MotionEvent.PointerProperties()};
        props[0].id = 0;
        props[0].toolType = android.view.MotionEvent.TOOL_TYPE_UNKNOWN;
        android.view.MotionEvent.PointerCoords[] coords = {new android.view.MotionEvent.PointerCoords()};
        for (int i = 0; i < AXES.length; i++) coords[0].setAxisValue(AXES[i], axisState[i]);
        inject(android.view.MotionEvent.obtain(now, now, android.view.MotionEvent.ACTION_MOVE, 1, props, coords, 0, 0, 1f, 1f,
                device, 0, android.view.InputDevice.SOURCE_JOYSTICK, 0));
    }

    /** Events carry the built-in controller's device id so games treat them as the Thor's own pad. */
    private static int gamepadDevice() {
        for (int id : android.view.InputDevice.getDeviceIds()) {
            android.view.InputDevice d = android.view.InputDevice.getDevice(id);
            if (d != null && (d.getSources() & android.view.InputDevice.SOURCE_GAMEPAD) == android.view.InputDevice.SOURCE_GAMEPAD) return id;
        }
        return -1;
    }

    private static void inject(android.view.InputEvent event) throws Exception {
        Object manager;
        try {
            manager = Class.forName("android.hardware.input.InputManagerGlobal").getMethod("getInstance").invoke(null);
        } catch (ClassNotFoundException olderAndroid) {
            manager = Class.forName("android.hardware.input.InputManager").getMethod("getInstance").invoke(null);
        }
        // Mode 0: asynchronous, so a slow app cannot stall the helper.
        Object ok = manager.getClass().getMethod("injectInputEvent", android.view.InputEvent.class, int.class).invoke(manager, event, 0);
        if (!Boolean.TRUE.equals(ok)) throw new IllegalStateException("Input rejected");
    }

    // ---- Virtual controller (app side) ----

    /** Forwards one validated controller event to the helper. */
    static void sendPad(Context c, JSONObject event) throws Exception {
        try (LocalSocket socket = new LocalSocket()) {
            socket.connect(new LocalSocketAddress(ThorControls.socketName(c), LocalSocketAddress.Namespace.ABSTRACT));
            socket.setSoTimeout(2000);
            if (socket.getPeerCredentials().getUid() != 2000) throw new SecurityException("Controls helper unavailable");
            byte[] request = new JSONObject(event.toString()).put("set", "pad").toString().getBytes(StandardCharsets.UTF_8);
            if (request.length > 180) throw new IllegalArgumentException("Event too long");
            DataOutputStream out = new DataOutputStream(socket.getOutputStream());
            out.writeShort(request.length); out.write(request); out.flush();
            if (socket.getInputStream().read() != 1) throw new IllegalStateException("Controller input rejected");
        }
    }

    /** Touch, Back or Home from the input channel: {"t":"i","value":0-3,"d":0|1,x,y,x2,y2,ms}. Same checks as the control path. */
    static void sendInput(Context c, JSONObject event) throws Exception {
        JSONObject request = new JSONObject().put("set", "input").put("value", integer(event, "value", 0, 3)).put("d", integer(event, "d", 0, 1));
        for (String k : new String[]{"x", "y", "x2", "y2", "ms"}) if (event.has(k)) request.put(k, event.get(k));
        inputCommand(request, new int[]{0, 1, 1});
        try (LocalSocket socket = new LocalSocket()) {
            socket.connect(new LocalSocketAddress(ThorControls.socketName(c), LocalSocketAddress.Namespace.ABSTRACT));
            socket.setSoTimeout(6000);
            if (socket.getPeerCredentials().getUid() != 2000) throw new SecurityException("Controls helper unavailable");
            byte[] bytes = request.toString().getBytes(StandardCharsets.UTF_8);
            DataOutputStream out = new DataOutputStream(socket.getOutputStream());
            out.writeShort(bytes.length); out.write(bytes); out.flush();
            DataInputStream in = new DataInputStream(socket.getInputStream());
            int length = in.readUnsignedShort();
            if (length > 256) throw new IOException("Reply too long");
            byte[] reply = new byte[length];
            in.readFully(reply);
            if (!new JSONObject(new String(reply, StandardCharsets.UTF_8)).optBoolean("ok")) throw new IllegalStateException("Input failed");
        }
    }

    static String scale(int fraction, int size) { return String.valueOf(Math.min(size - 1, (int) ((long) fraction * size / 10000))); }

    static int integer(JSONObject j, String key, int min, int max) throws Exception {
        Object raw = j.get(key);
        if (!(raw instanceof Number) || ((Number) raw).doubleValue() != ((Number) raw).intValue()) throw new IllegalArgumentException("Integer required");
        int value = ((Number) raw).intValue();
        if (value < min || value > max) throw new IllegalArgumentException("Value out of range");
        return value;
    }

    // ---- App side ----

    private static final AtomicInteger appStreams = new AtomicInteger();
    private static PowerManager.WakeLock screens;

    /** Opens a helper stream; the caller must close it. Keeps the Thor's screens on while any stream is open. */
    static InputStream open(Context c, int screen, int quality) throws Exception {
        LocalSocket socket = new LocalSocket();
        try {
            socket.connect(new LocalSocketAddress(ThorControls.socketName(c), LocalSocketAddress.Namespace.ABSTRACT));
            socket.setSoTimeout(10000);
            if (socket.getPeerCredentials().getUid() != 2000) throw new SecurityException("Controls helper unavailable");
            byte[] request = new JSONObject().put("set", "stream_open").put("value", screen).put("quality", quality).toString().getBytes(StandardCharsets.UTF_8);
            DataOutputStream out = new DataOutputStream(socket.getOutputStream());
            out.writeShort(request.length); out.write(request); out.flush();
            if (socket.getInputStream().read() != 1) throw new IllegalStateException("Live view unavailable. Close another live view or check Controls recovery.");
            socket.setSoTimeout(0); // a still screen sends nothing for a long time
        } catch (Exception e) {
            socket.close();
            throw e;
        }
        holdScreens(c, +1);
        return new FilterInputStream(socket.getInputStream()) {
            boolean closed;
            @Override public void close() throws IOException {
                if (closed) return;
                closed = true;
                // shutdown wakes a relay blocked in read and tells the helper to stop recording.
                try { socket.shutdownInput(); socket.shutdownOutput(); } catch (IOException ignored) {}
                try { socket.close(); } finally { holdScreens(c, -1); }
            }
        };
    }

    private static synchronized void holdScreens(Context c, int delta) {
        if (screens == null) {
            screens = c.getApplicationContext().getSystemService(PowerManager.class)
                    .newWakeLock(PowerManager.SCREEN_BRIGHT_WAKE_LOCK | PowerManager.ACQUIRE_CAUSES_WAKEUP, "ThorMonitor:LiveView");
            screens.setReferenceCounted(false);
        }
        if (appStreams.addAndGet(delta) > 0) screens.acquire(MAX_MS + 60000);
        else if (screens.isHeld()) screens.release();
    }
}
