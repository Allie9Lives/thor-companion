package com.alan.thormonitor;
import java.io.*;import java.nio.charset.StandardCharsets;import java.util.*;
public class WebSecurityTest {
 static int checks;static void check(boolean b,String name){if(!b)throw new AssertionError(name);checks++;}
 static WebHttp.Request parse(String s)throws Exception{return WebHttp.read(new ByteArrayInputStream(s.getBytes(StandardCharsets.US_ASCII)));}
 static void bad(String s)throws Exception{try{parse(s);throw new AssertionError("Accepted malformed request");}catch(IOException|java.net.URISyntaxException|IllegalArgumentException expected){checks++;}}
 public static void main(String[] args)throws Exception{
  byte[] salt=WebSessions.salt();char[] password="test-password-for-web".toCharArray();byte[] hash=WebSessions.derive(password,salt);
  check(WebSessions.verify("owner",password,"owner",salt,hash),"Valid owner");check(!WebSessions.verify("other",password,"owner",salt,hash),"Wrong owner");check(!WebSessions.verify("owner","different-password".toCharArray(),"owner",salt,hash),"Wrong password");check(!Arrays.equals(hash,WebSessions.derive(password,WebSessions.salt())),"Unique salt");
  try{WebSessions.validate("owner","short".toCharArray());throw new AssertionError();}catch(IllegalArgumentException expected){checks++;}
  WebSessions sessions=new WebSessions();WebSessions.Session s=sessions.create("https://thor:47184",100);
  check(sessions.get(s.cookie,s.origin,101)==s,"Cookie lookup");check(sessions.get(s.cookie,"https://other:47184",101)==null,"Origin binding");check(sessions.get(s.csrf,s.origin,101)==null,"CSRF is not cookie");
  check(!sessions.touch(s,"wrong",102),"Reject invalid CSRF");check(sessions.awake(100+WebSessions.WAKE_MS-1),"Active wake hold");check(!sessions.awake(100+WebSessions.WAKE_MS),"Wake hold expires without polling renewal");check(sessions.touch(s,s.csrf,700000),"Interaction renews");check(sessions.awake(700001),"Renewed wake hold");check(sessions.get(s.cookie,s.origin,700000+WebSessions.IDLE_MS)==null,"Idle expiry");
  s=sessions.create("https://thor",10);check(!sessions.touch(s,s.csrf,10+WebSessions.MAX_MS),"Absolute expiry");sessions.clear();check(sessions.count(0)==0,"Revocation");check(!sessions.touch(s,s.csrf,11),"Cannot revive revoked session");
  for(int n=0;n<8;n++)check(sessions.create("https://thor",20)!=null,"Bounded session slot");check(sessions.create("https://thor",20)==null,"Session cap");
  for(int n=0;n<5;n++)check(sessions.allowLogin("peer",1000),"Login attempt");check(!sessions.allowLogin("peer",1001),"Peer rate limit");check(sessions.allowLogin("peer",301001),"Rate window recovers");
  String good="GET /api/state HTTP/1.1\r\nHost: 127.0.0.1:47184\r\n\r\n";check(parse(good).path.equals("/api/state"),"Valid request");
  bad(good.replace("\r\n","\n"));bad(good.replace("Host:","Host: duplicate\r\nHost:"));bad(good.replace("Host:","Transfer-Encoding: chunked\r\nHost:"));bad(good.replace("Host:","Content-Length: 1\r\nHost:"));bad(good.replace("Host:","Content-Length: -1\r\nHost:"));bad(good.replace("Host:","X-Bad: a\rb\r\nHost:"));bad(good.replace("/api/state","//evil/path"));bad(good.replace("/api/state","/x?key=a&key=b"));bad(good.replace("/api/state","/x#fragment"));bad(good.replace("/api/state","/x?key=%ZZ"));
  WebHttp.Request req=parse(good.replace("Host:","Cookie: __Host-thor_web=a; __Host-thor_web=b\r\nHost:"));check(WebHttp.cookie(req)==null,"Duplicate cookies rejected");
  ByteArrayOutputStream out=new ByteArrayOutputStream();WebHttp.bytes(out,200,"application/json",new byte[]{123,125},null);String headers=out.toString("US-ASCII");check(headers.contains("frame-ancestors 'none'")&&headers.contains("Cache-Control: no-store")&&headers.contains("Content-Length: 2"),"Response protections");
  System.out.println(checks+" Web Ops security checks passed");
 }
}
