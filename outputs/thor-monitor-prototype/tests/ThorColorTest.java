package com.alan.thormonitor;
public class ThorColorTest {
 public static void main(String[] args){
  if(!ThorColor.theme("black").equals("dark")||!ThorColor.theme("white").equals("light")||!ThorColor.theme("clearPurple").equals("clearPurple")||!ThorColor.theme("rainbow").equals("rainbow"))throw new AssertionError("Color/theme mapping");
  for(int i=0;i<4;i++)if(ThorColor.index(ThorColor.VALUES[i])!=i)throw new AssertionError("Choice index");
  if(ThorColor.index(null)!=-1||ThorColor.index("unknown")!=-1)throw new AssertionError("Unknown choice");
  try{ThorColor.theme("unknown");throw new AssertionError("Invalid choice allowed");}catch(IllegalArgumentException expected){}
  System.out.println("Thor shell color mappings passed.");
 }
}
