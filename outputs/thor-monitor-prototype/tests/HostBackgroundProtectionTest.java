package com.alan.thormonitor;
public final class HostBackgroundProtectionTest {
 static int checks;
 static void check(boolean value){if(!value)throw new AssertionError();checks++;}
 public static void main(String[] args){
  String p="com.alan.thormonitor",other="com.example.music,com.example.vpn";
  check(HostBackgroundProtection.update(null,p,true).equals(p));
  check(HostBackgroundProtection.update("",p,true).equals(p));
  check(HostBackgroundProtection.update(other,p,true).equals(other+","+p));
  check(HostBackgroundProtection.update(other+","+p,p,true).equals(other+","+p));
  check(!HostBackgroundProtection.contains(p+".other",p));
  check(HostBackgroundProtection.update(other+","+p,p,false).equals(other));
  check(HostBackgroundProtection.update(p+","+other,p,false).equals(other));
  check(HostBackgroundProtection.update(p,p,false).equals(""));
  check(HostBackgroundProtection.update(null,p,false)==null);
  check(HostBackgroundProtection.update(other,p,false).equals(other));
  System.out.println("PASS: "+checks+" launcher exemption checks");
 }
}
