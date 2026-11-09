package com.alan.thormonitor;
/** Shared host/UI overlay colors; identifiers match the companion preferences. */
final class HostPalette {
 final boolean dark,rainbow;final int bg,card,ink,muted,border,accent,onAccent;
 static final int[] RAINBOW={0xFFC08A00,0xFF24794B,0xFF285BC5,0xFFBA4141};
 private HostPalette(boolean d,boolean r,int bg,int card,int ink,int muted,int border,int accent,int onAccent){this.dark=d;this.rainbow=r;this.bg=bg;this.card=card;this.ink=ink;this.muted=muted;this.border=border;this.accent=accent;this.onAccent=onAccent;}
 static HostPalette resolve(String theme,boolean systemDark){
  if("clearPurple".equals(theme))return new HostPalette(true,false,0xFF1D1825,0xFF2C2438,0xFFF5EFFB,0xFFC5B9D3,0xFF4D405F,0xFFC6B2E5,0xFF281B3A);
  if("rainbow".equals(theme))return new HostPalette(false,true,0xFFFAFBFD,0xFFFFFFFF,0xFF202630,0xFF596474,0xFFDCE2EB,0xFF285BC5,0xFFFFFFFF);
  boolean dark="dark".equals(theme)||!"light".equals(theme)&&systemDark;
  return dark?new HostPalette(true,false,0xFF111113,0xFF1C1C1F,0xFFF5F5F7,0xFFA2A2AA,0xFF333337,0xFFE7E7EB,0xFF18181B):new HostPalette(false,false,0xFFF2F2F5,0xFFFFFFFF,0xFF19191C,0xFF63636C,0xFFDEDEE3,0xFF252529,0xFFFFFFFF);
 }
}
