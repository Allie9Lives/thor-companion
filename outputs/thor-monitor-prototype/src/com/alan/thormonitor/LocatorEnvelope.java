package com.alan.thormonitor;
final class LocatorEnvelope {
    static float amplitude(long elapsed){double t=Math.max(0,Math.min(1,elapsed/120.0));return (float)(.85+.15*t);}
    static float fadeOut(float from,long elapsed){double t=Math.max(0,Math.min(1,elapsed/220.0));return (float)(from*(.5+.5*Math.cos(Math.PI*t)));}
}
