package com.alan.thormonitor;
import java.nio.*;
import java.util.*;
import java.util.zip.CRC32;
public class CaptureBufferTest {
 public static void main(String[] args){
  byte[] image=new byte[40000];new Random(7).nextBytes(image);
  CaptureBuffer b=new CaptureBuffer(image,-15);CRC32 crc=new CRC32();crc.update(image);
  if(b.crc!=crc.getValue())throw new AssertionError("CRC mismatch");
  for(int mtu:new int[]{40,185,517}){
   int offset=0;java.io.ByteArrayOutputStream result=new java.io.ByteArrayOutputStream();
   while(offset<image.length){byte[] packet=b.packet(offset,mtu);ByteBuffer p=ByteBuffer.wrap(packet);
    if(p.getInt()!=0x54533031 || p.getInt()!=-15 || p.getInt()!=offset || p.getInt()!=image.length || packet.length>mtu-3)throw new AssertionError("Packet header/MTU");
    result.write(packet,16,packet.length-16);offset+=packet.length-16;
   }
   if(!Arrays.equals(image,result.toByteArray()))throw new AssertionError("Payload mismatch");
  }
  try{b.packet(40000,185);throw new AssertionError("Invalid offset accepted");}catch(IllegalArgumentException expected){}
  try{b.packet(0,23);throw new AssertionError("Insufficient MTU accepted");}catch(IllegalArgumentException expected){}
  System.out.println("Capture packet tests passed: MTU bounds, ordered bytes, CRC, invalid offsets.");
 }
}
