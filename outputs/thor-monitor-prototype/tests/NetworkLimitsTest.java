package com.alan.thormonitor;
/** Companion peer filter and transfer budget (F-008, F-010). */
public final class NetworkLimitsTest {
 static byte[] ip(int... v){byte[] b=new byte[v.length];for(int i=0;i<v.length;i++)b[i]=(byte)v[i];return b;}
 public static void main(String[] args)throws Exception{
  if(!FileAccess.samePrefix(ip(203,0,113,7),ip(203,0,113,200),24))throw new AssertionError("Same public /24 subnet must be allowed");
  if(FileAccess.samePrefix(ip(203,0,113,7),ip(203,0,114,7),24))throw new AssertionError("Other subnet allowed");
  if(FileAccess.samePrefix(ip(203,0,113,7),ip(8,8,8,8),0)||FileAccess.samePrefix(ip(203,0,113,7),ip(203,9,9,9),4))throw new AssertionError("Implausibly wide prefix allowed");
  if(FileAccess.samePrefix(ip(10,0,0,1),new byte[16],24))throw new AssertionError("Mixed address families allowed");
  if(!FileAccess.samePrefix(ip(192,168,1,1),ip(192,168,1,1),32)||FileAccess.samePrefix(ip(192,168,1,1),ip(192,168,1,2),33))throw new AssertionError("Prefix bounds");
  if(!WebTls.privateAddress(java.net.InetAddress.getByAddress(ip(100,101,102,103)))||WebTls.privateAddress(java.net.InetAddress.getByAddress(ip(8,8,8,8))))throw new AssertionError("VPN/private classification");
  long gib=1L<<30;
  if(WebHttp.transferBudget(10*1024*1024,20*60000L)!=20*60000L)throw new AssertionError("Small files keep the floor");
  if(WebHttp.transferBudget(64*gib,20*60000L)<64*gib/1000)throw new AssertionError("64 GiB at 1 MB/s must fit the budget");
  if(WebHttp.transferBudget(-1,30*60000L)!=30*60000L)throw new AssertionError("Unknown size");
  System.out.println("Peer subnet filter, VPN classification and size-based transfer budget passed.");
 }
}
