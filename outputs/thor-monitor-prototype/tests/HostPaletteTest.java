package com.alan.thormonitor;
public class HostPaletteTest {
 public static void main(String[] args){
  HostPalette light=HostPalette.resolve("light",true),dark=HostPalette.resolve("dark",false),purple=HostPalette.resolve("clearPurple",false),rainbow=HostPalette.resolve("rainbow",true);
  if(light.dark||!dark.dark||!purple.dark||rainbow.dark||!rainbow.rainbow||purple.card!=0xFF2C2438||purple.accent!=0xFFC6B2E5)throw new AssertionError("Theme mapping");
  if(!HostPalette.resolve("system",true).dark||HostPalette.resolve("system",false).dark)throw new AssertionError("System appearance");
  for(HostPalette p:new HostPalette[]{light,dark,purple,rainbow}){if(contrast(p.ink,p.card)<4.5||contrast(p.muted,p.card)<4.5||contrast(p.onAccent,p.accent)<4.5)throw new AssertionError("Text contrast");}
  System.out.println("Host palettes and contrast passed.");
 }
 static double lum(int c){double r=channel((c>>16)&255),g=channel((c>>8)&255),b=channel(c&255);return .2126*r+.7152*g+.0722*b;}
 static double channel(int c){double v=c/255.0;return v<=.04045?v/12.92:Math.pow((v+.055)/1.055,2.4);}
 static double contrast(int a,int b){double x=lum(a),y=lum(b);return (Math.max(x,y)+.05)/(Math.min(x,y)+.05);}
}
