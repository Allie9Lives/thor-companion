package com.alan.thormonitor;
public class StickNavigationTest {
 static int checks;
 static void eq(int actual,int expected,String name){if(actual!=expected)throw new AssertionError(name+": "+actual);checks++;}
 public static void main(String[] args){
  StickNavigation n=new StickNavigation();
  eq(n.next(.4f,.5f,0),0,"Ignore partial deflection");
  eq(n.next(0,1,10),130,"First intentional movement");
  eq(n.next(0,1,180),0,"No former fast repeat");
  eq(n.next(0,1,469),0,"Wait initial delay");
  eq(n.next(0,1,470),130,"Initial held repeat");
  eq(n.next(0,1,729),0,"Wait repeat interval");
  eq(n.next(0,1,730),130,"Slower held repeat");
  eq(n.next(.9f,.88f,1000),0,"Diagonal jitter does not switch direction");
  eq(n.next(1,0,1000),66,"Deliberate direction change");
  eq(n.next(0,0,1010),0,"Neutral resets latch");
  eq(n.next(-1,0,1020),17,"Next tap responds immediately");
  eq(n.next(Float.NaN,0,1030),0,"Invalid axis ignored");
  eq(n.next(0,-1,1040),33,"Up after reset");
  eq(n.next(0,-.5f,2000),0,"Partial hold does not repeat");
  n.reset();eq(n.next(.7f,0,3000),0,"Reset on pause");
  System.out.println("PASS: "+checks+" joystick navigation checks");
 }
}
