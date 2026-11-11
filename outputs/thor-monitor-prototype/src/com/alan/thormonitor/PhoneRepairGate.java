package com.alan.thormonitor;

import java.util.LinkedHashMap;

/** Recent denied bonded peers are candidates, never automatically authorized. */
final class PhoneRepairGate {
    static final long WINDOW_MS=5*60*1000;
    private final LinkedHashMap<String,Long> pending=new LinkedHashMap<>();
    private void prune(long now){pending.entrySet().removeIf(e->now-e.getValue()<0||now-e.getValue()>WINDOW_MS);}
    synchronized boolean record(String address,long now){prune(now);boolean fresh=!pending.containsKey(address);pending.put(address,now);while(pending.size()>8)pending.remove(pending.keySet().iterator().next());return fresh;}
    synchronized boolean contains(String address,long now){prune(now);return pending.containsKey(address);}
    synchronized void clear(){pending.clear();}
}
