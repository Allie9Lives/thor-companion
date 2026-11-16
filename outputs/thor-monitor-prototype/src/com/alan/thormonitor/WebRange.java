package com.alan.thormonitor;
import java.io.*;
/** One RFC 9110 byte range; malformed and multi-range requests are rejected. */
final class WebRange {
 final long start,end,total;final boolean partial;
 private WebRange(long a,long b,long n,boolean p){start=a;end=b;total=n;partial=p;}
 long length(){return end<start?0:end-start+1;}
 static WebRange parse(String header,long size){
  if(size<0)throw new IllegalArgumentException("Unknown file size");if(header==null||header.isEmpty())return new WebRange(0,size-1,size,false);
  if(size==0||!header.matches("bytes=[0-9]*-[0-9]*")||header.length()>60)throw new IllegalArgumentException("Invalid byte range");
  String[] p=header.substring(6).split("-",-1);long a,b;
  try{if(p[0].isEmpty()){long count=Long.parseLong(p[1]);if(count<=0)throw new IllegalArgumentException();a=Math.max(0,size-count);b=size-1;}else{a=Long.parseLong(p[0]);b=p[1].isEmpty()?size-1:Math.min(size-1,Long.parseLong(p[1]));if(a>=size||b<a)throw new IllegalArgumentException();}}catch(NumberFormatException e){throw new IllegalArgumentException("Invalid byte range");}
  return new WebRange(a,b,size,true);
 }
 static void seek(InputStream in,long position)throws IOException{if(in instanceof FileInputStream){((FileInputStream)in).getChannel().position(position);return;}while(position>0){long n=in.skip(position);if(n==0){if(in.read()<0)throw new EOFException();n=1;}position-=n;}}
 String headers(){return "Accept-Ranges: bytes\r\n"+(partial?"Content-Range: bytes "+start+"-"+end+"/"+total+"\r\n":"");}
}
