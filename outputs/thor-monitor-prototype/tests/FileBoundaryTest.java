package com.alan.thormonitor;
import java.io.*;import java.nio.file.*;
public final class FileBoundaryTest {
 interface Action{void run()throws Exception;}
 static void rejects(Action a)throws Exception{try{a.run();throw new AssertionError("Path allowed");}catch(IllegalArgumentException|SecurityException expected){}}
 public static void main(String[] args)throws Exception{
  Path base=Files.createTempDirectory("thor-boundary-test"),root=Files.createDirectory(base.resolve("root")),outside=Files.createDirectory(base.resolve("outside"));
  try{Files.createSymbolicLink(root.resolve("escape"),outside);
   if(!SharedFiles.resolve(root.toFile(),"").equals(root.toFile().getCanonicalFile()))throw new AssertionError();
   if(!SharedFiles.resolve(root.toFile(),"ROMs/L'été.bin").getPath().endsWith("ROMs/L'été.bin"))throw new AssertionError();
   rejects(()->SharedFiles.resolve(root.toFile(),"../outside"));rejects(()->SharedFiles.resolve(root.toFile(),"escape/private"));rejects(()->SharedFiles.resolve(root.toFile(),"Android/data/other.app"));rejects(()->SharedFiles.resolve(root.toFile(),"Android/obb/other.app"));rejects(()->SharedFiles.resolve(root.toFile(),"a//b"));rejects(()->FileAccess.validateName("bad\\name"));rejects(()->FileAccess.validateName("bad\nname"));
   System.out.println("Shared-root containment, protected directories and filename tests passed");
  }finally{Files.deleteIfExists(root.resolve("escape"));Files.delete(root);Files.delete(outside);Files.delete(base);}
 }
}
