package com.alan.thormonitor;

import java.security.*;
import java.util.*;
import javax.crypto.SecretKeyFactory;
import javax.crypto.spec.PBEKeySpec;

/** Browser-only credentials and sessions; no native pairing/token dependencies. */
final class WebSessions {
    static final int ITERATIONS=600000;
    static final long IDLE_MS=30*60000L, MAX_MS=8*60*60000L, WAKE_MS=10*60000L;
    private static final SecureRandom random=new SecureRandom();
    static String token(){byte[] b=new byte[32];random.nextBytes(b);return Base64.getUrlEncoder().withoutPadding().encodeToString(b);}
    static byte[] salt(){byte[] b=new byte[32];random.nextBytes(b);return b;}
    static byte[] derive(char[] password,byte[] salt)throws Exception{
        PBEKeySpec spec=new PBEKeySpec(password,salt,ITERATIONS,256);
        try{return SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256").generateSecret(spec).getEncoded();}finally{spec.clearPassword();}
    }
    static void validate(String user,char[] password){
        if(user==null||!user.matches("[A-Za-z0-9_.@-]{3,64}"))throw new IllegalArgumentException("Username: 3–64 letters, numbers, dots, @, underscores or hyphens.");
        if(password==null||password.length<12||password.length>128)throw new IllegalArgumentException("Use a password with 12–128 characters.");
        for(char c:password)if(c==0)throw new IllegalArgumentException("Invalid password character.");
    }
    static boolean verify(String user,char[] password,String expectedUser,byte[] salt,byte[] expected)throws Exception{
        byte[] actual=derive(password,salt);
        try{return MessageDigest.isEqual(actual,expected)&MessageDigest.isEqual(user.getBytes("UTF-8"),expectedUser.getBytes("UTF-8"));}finally{Arrays.fill(actual,(byte)0);}
    }
    static final class Session {
        final String id=token(),cookie=token(),csrf=token(),origin;String label="Browser";long idleLimit=IDLE_MS;final long created;long interacted;
        Session(String origin,long now){this.origin=origin;created=interacted=now;}
        boolean valid(long now){return now>=created&&now-created<MAX_MS&&now-interacted<idleLimit;}
    }
    private long idleLimit=IDLE_MS;
    private final LinkedHashMap<String,Session> sessions=new LinkedHashMap<>();
    private final LinkedHashMap<String,ArrayDeque<Long>> attempts=new LinkedHashMap<>();
    private final ArrayDeque<Long> globalAttempts=new ArrayDeque<>();
    private static String key(String cookie){try{return Base64.getEncoder().encodeToString(MessageDigest.getInstance("SHA-256").digest(cookie.getBytes("US-ASCII")));}catch(Exception e){throw new IllegalStateException(e);}}
    synchronized boolean allowLogin(String peer,long now){
        globalAttempts.removeIf(t->now-t>=60000);attempts.entrySet().removeIf(e->e.getValue().isEmpty()||now-e.getValue().getLast()>=5*60000L);
        ArrayDeque<Long> failures=attempts.get(peer);if(failures!=null)failures.removeIf(t->now-t>=5*60000L);
        if(globalAttempts.size()>=20||failures!=null&&failures.size()>=5)return false;
        if(failures==null){if(attempts.size()>=256)attempts.remove(attempts.keySet().iterator().next());failures=new ArrayDeque<>();attempts.put(peer,failures);}
        failures.add(now);globalAttempts.add(now);return true;
    }
    synchronized Session create(String origin,long now){
        sessions.entrySet().removeIf(e->!e.getValue().valid(now));if(sessions.size()>=8)return null;
        Session s=new Session(origin,now);s.idleLimit=idleLimit;sessions.put(key(s.cookie),s);return s;
    }
    synchronized Session get(String cookie,String origin,long now){
        if(cookie==null||!cookie.matches("[A-Za-z0-9_-]{43}"))return null;
        Session s=sessions.get(key(cookie));if(s==null)return null;
        if(!s.valid(now)){sessions.remove(key(cookie));return null;}return s.origin.equals(origin)?s:null;
    }
    synchronized boolean touch(Session s,String csrf,long now){
        if(s==null||!sessions.containsValue(s)||!s.valid(now)||csrf==null||!MessageDigest.isEqual(s.csrf.getBytes(java.nio.charset.StandardCharsets.US_ASCII),csrf.getBytes(java.nio.charset.StandardCharsets.US_ASCII)))return false;
        s.interacted=now;return true;
    }
    synchronized void idleMinutes(int minutes){if(minutes<15||minutes>120)throw new IllegalArgumentException("Use 15–120 minutes");idleLimit=minutes*60000L;for(Session s:sessions.values())s.idleLimit=idleLimit;}
    synchronized java.util.List<Session> list(long now){count(now);return new ArrayList<>(sessions.values());}
    synchronized boolean revoke(String id){return sessions.values().removeIf(s->s.id.equals(id));}
    static String clientLabel(String agent){String browser=agent.contains("Edg/")?"Edge":agent.contains("Firefox/")?"Firefox":agent.contains("Chrome/")?"Chrome":agent.contains("Safari/")?"Safari":"Browser";return browser+(agent.contains("Windows")?" · Windows":agent.contains("Android")?" · Android":agent.contains("iPhone")||agent.contains("iPad")?" · iOS":agent.contains("Macintosh")?" · Mac":agent.contains("Linux")?" · Linux":"");}
    synchronized void remove(Session s){sessions.values().remove(s);}
    synchronized void clear(){sessions.clear();}
    synchronized int count(long now){sessions.entrySet().removeIf(e->!e.getValue().valid(now));return sessions.size();}
    synchronized boolean awake(long now){for(Session s:sessions.values())if(s.valid(now)&&now-s.interacted<WAKE_MS)return true;return false;}
}
