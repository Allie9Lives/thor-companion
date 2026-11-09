package com.alan.thormonitor;
public class CommandReplayTest {
 public static void main(String[] args){CommandReplay c=new CommandReplay();byte[] text="private typing".getBytes();c.save("one",text,"reply",1000);if(!"reply".equals(c.find("one",text,2000)))throw new AssertionError("Retry receipt missing");
  try{c.find("one","changed".getBytes(),2000);throw new AssertionError("Reused ID accepted");}catch(IllegalArgumentException expected){}
  if(c.entries.get("one").digest.length!=32)throw new AssertionError("Must keep a digest");
  if(c.find("one",text,302000)!=null)throw new AssertionError("Expired receipt");for(int i=0;i<300;i++)c.save("id"+i,text,"r",400000);if(c.entries.size()!=256)throw new AssertionError("Unbounded cache");
  System.out.println("Retry receipt, conflicting payload, expiry and bounds passed.");
 }
}
