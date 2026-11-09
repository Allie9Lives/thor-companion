package com.alan.thormonitor;
import java.util.*;import java.security.*;
/** Bounded in-memory retry receipts. Retains a digest, never keyboard text. */
final class CommandReplay {
 static final class Receipt {final byte[] digest;final String reply;final long at;Receipt(byte[] d,String r,long t){digest=d;reply=r;at=t;}}
 final LinkedHashMap<String,Receipt> entries=new LinkedHashMap<>();
 private byte[] digest(byte[] bytes){try{return MessageDigest.getInstance("SHA-256").digest(bytes);}catch(Exception e){throw new IllegalStateException(e);}}
 private void prune(long now){entries.entrySet().removeIf(e->now-e.getValue().at>300000);}
 String find(String id,byte[] bytes,long now){prune(now);Receipt r=entries.get(id);if(r==null)return null;if(!MessageDigest.isEqual(r.digest,digest(bytes)))throw new IllegalArgumentException("Request ID already used");return r.reply;}
 void save(String id,byte[] bytes,String reply,long now){prune(now);if(entries.size()>=256)entries.remove(entries.keySet().iterator().next());entries.put(id,new Receipt(digest(bytes),reply,now));}
}
