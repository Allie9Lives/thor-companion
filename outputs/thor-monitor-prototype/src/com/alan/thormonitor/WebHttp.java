package com.alan.thormonitor;
import java.io.*;import java.net.*;import java.nio.charset.StandardCharsets;import java.util.*;

/** One bounded request per connection. Never accepts ambiguous framing. */
final class WebHttp {
    static final class Request {
        String method,path,host;long length;final Map<String,String> headers=new HashMap<>(),query=new HashMap<>();
        String header(String name){return headers.getOrDefault(name,"");}
        byte[] body(InputStream in,int max)throws IOException{if(length<0||length>max)throw new IOException("Request body too large");byte[] b=new byte[(int)length];new DataInputStream(in).readFully(b);return b;}
    }
    static String line(InputStream in,int max)throws IOException{
        ByteArrayOutputStream b=new ByteArrayOutputStream();int last=-1;
        for(int n;(n=in.read())!=-1;){if(n=='\n'){if(last!='\r')throw new IOException("Invalid line ending");byte[] a=b.toByteArray();return new String(a,0,a.length-1,StandardCharsets.US_ASCII);}if(last=='\r'||n<32&&n!='\r'||n>126||b.size()>=max)throw new IOException("Invalid HTTP header");b.write(n);last=n;}throw new EOFException();
    }
    static Request read(InputStream in)throws Exception{
        Request r=new Request();String[] parts=line(in,8192).split(" ",-1);
        if(parts.length!=3||!parts[2].equals("HTTP/1.1")||!Arrays.asList("GET","HEAD","POST","PUT").contains(parts[0])||!parts[1].startsWith("/")||parts[1].startsWith("//"))throw new IOException("Invalid request");
        r.method=parts[0];int total=0,count=0;
        while(true){String h=line(in,8192);total+=h.length();if(total>16384||++count>40)throw new IOException("Too many headers");if(h.isEmpty())break;int i=h.indexOf(':');if(i<1)throw new IOException("Invalid header");String name=h.substring(0,i).toLowerCase(Locale.ROOT);if(!name.matches("[a-z0-9-]+")||r.headers.put(name,h.substring(i+1).trim())!=null)throw new IOException("Duplicate header");}
        r.host=r.header("host");if(r.host.isEmpty()||r.headers.containsKey("transfer-encoding"))throw new IOException("Invalid framing");
        String len=r.header("content-length");if(!len.isEmpty()&&!len.matches("[0-9]{1,12}"))throw new IOException("Invalid length");r.length=len.isEmpty()?0:Long.parseLong(len);if(r.length>64L*1024*1024*1024)throw new IOException("Request too large");if((r.method.equals("GET")||r.method.equals("HEAD"))&&r.length!=0)throw new IOException("GET body rejected");
        URI u=new URI(parts[1]);if(u.getFragment()!=null||u.getHost()!=null)throw new IOException("Invalid URL");r.path=u.getPath();if(r.path.indexOf('\0')>=0)throw new IOException("Invalid path");
        if(u.getRawQuery()!=null)for(String p:u.getRawQuery().split("&")){String[] kv=p.split("=",2);String k=URLDecoder.decode(kv[0],"UTF-8"),v=URLDecoder.decode(kv.length==2?kv[1]:"","UTF-8");if(r.query.put(k,v)!=null)throw new IOException("Duplicate query");}
        return r;
    }
    static String cookie(Request r){String result=null;for(String item:r.header("cookie").split(";")){String[] p=item.trim().split("=",2);if(p.length==2&&p[0].equals("__Host-thor_web")){if(result!=null)return null;result=p[1];}}return result;}
    static void head(OutputStream out,int status,String type,long length,String extra)throws IOException{
        String headers="HTTP/1.1 "+status+" Response\r\nContent-Type: "+type+"\r\nContent-Length: "+length+"\r\nConnection: close\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nReferrer-Policy: no-referrer\r\nX-Frame-Options: DENY\r\nContent-Security-Policy: default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self' data: blob:; connect-src 'self'; media-src 'self' blob:; base-uri 'none'; frame-ancestors 'none'; form-action 'self'\r\nPermissions-Policy: camera=(), microphone=(), geolocation=()\r\n"+(extra==null?"":extra)+"\r\n";
        out.write(headers.getBytes(StandardCharsets.US_ASCII));
    }
    private static final java.util.concurrent.ScheduledExecutorService deadlines=java.util.concurrent.Executors.newSingleThreadScheduledExecutor(r->{Thread t=new Thread(r,"http-deadline");t.setDaemon(true);return t;});
    /** Closes a connection whose TLS handshake and request headers are not complete in time, so slow clients cannot hold workers. */
    static java.util.concurrent.ScheduledFuture<?> deadline(Socket s,long ms){return deadlines.schedule(()->{try{s.close();}catch(Exception ignored){}},ms,java.util.concurrent.TimeUnit.MILLISECONDS);}
    /** Absolute transfer budget: at least {@code floorMs}, otherwise five minutes plus the time to move {@code size} bytes at 1 MB/s. Stalls are caught by socket read timeouts. */
    static long transferBudget(long size,long floorMs){return Math.max(floorMs,5*60000L+Math.max(0,size)/1000);}
    static void bytes(OutputStream out,int status,String type,byte[] bytes,String extra)throws IOException{head(out,status,type,bytes.length,extra);out.write(bytes);out.flush();}
}
