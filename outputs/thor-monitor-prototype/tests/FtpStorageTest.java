package com.alan.thormonitor;
import java.io.*;import java.nio.file.*;import java.util.*;import org.apache.ftpserver.ftplet.*;
public class FtpStorageTest {
 public static void main(String[] args)throws Exception{
  File area=Files.createTempDirectory("thor-ftp-test").toFile(),internal=new File(area,"internal"),sd=new File(area,"sd");internal.mkdir();sd.mkdir();Map<String,File> roots=new LinkedHashMap<>();roots.put("internal",internal);roots.put("sd",sd);FtpStorage fs=new FtpStorage(()->roots);
  if(fs.getHomeDirectory().listFiles().size()!=2)throw new AssertionError("Both shared roots missing");
  FtpFile file=fs.getFile("/internal/hello.bin");try(OutputStream out=file.createOutputStream(0)){out.write(new byte[]{1,2,3});}
  try(InputStream in=file.createInputStream(1)){if(in.read()!=2)throw new AssertionError("Download resume offset");}
  try(OutputStream out=file.createOutputStream(3)){out.write(4);}if(file.getSize()!=4)throw new AssertionError("Upload resume");
  if(!fs.changeWorkingDirectory("/internal")||!fs.getFile("../sd").isDirectory())throw new AssertionError("Storage navigation");
  if(fs.getFile("/internal").delete()||fs.getFile("/sd").delete())throw new AssertionError("Storage root deletion permitted");
  for(String path:new String[]{"/../escape","/internal/Android/data/secret","/internal/Android/OBB/private","/internal/foo\\bar"})try{FtpFile f=fs.getFile(path);f.createOutputStream(0);throw new AssertionError("Forbidden path accepted: "+path);}catch(IOException|FtpException expected){}
  File outside=new File(area,"outside");outside.mkdir();Files.createSymbolicLink(new File(internal,"link").toPath(),outside.toPath());if(fs.getFile("/internal/link/escape").isWritable())throw new AssertionError("Symlink escaped storage");
  roots.clear();if(file.isReadable()||file.isWritable())throw new AssertionError("Revoked grant still accessible");
  System.out.println("FTP roots, upload/download resume, traversal, private directories, symlinks and revocation passed.");
 }
}
