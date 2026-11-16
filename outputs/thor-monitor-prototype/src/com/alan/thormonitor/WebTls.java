package com.alan.thormonitor;

import android.content.Context;import android.security.keystore.*;
import java.io.*;import java.net.*;import java.security.*;import java.security.cert.*;import java.util.*;import java.math.BigInteger;
import javax.net.ssl.*;import javax.security.auth.x500.X500Principal;
import org.bouncycastle.asn1.*;import org.bouncycastle.asn1.x509.*;import org.bouncycastle.asn1.x500.X500Name;import org.bouncycastle.asn1.x9.X9ObjectIdentifiers;

/** Per-device CA and server keys remain non-exportable in AndroidKeyStore. */
final class WebTls {
    private static final String ROOT="thor-web-ca-v1",LEAF="thor-web-server-v2";
    private static final long DAY=86400000L;
    private static X509Certificate ca;
    private static KeyStore store()throws Exception{KeyStore k=KeyStore.getInstance("AndroidKeyStore");k.load(null);return k;}
    private static KeyPair key(KeyStore k,String alias,String name)throws Exception{
        if(!k.containsAlias(alias)){
            KeyPairGenerator g=KeyPairGenerator.getInstance("EC","AndroidKeyStore");g.initialize(new KeyGenParameterSpec.Builder(alias,KeyProperties.PURPOSE_SIGN|KeyProperties.PURPOSE_VERIFY)
                .setAlgorithmParameterSpec(new java.security.spec.ECGenParameterSpec("secp256r1")).setDigests(KeyProperties.DIGEST_NONE,KeyProperties.DIGEST_SHA256,KeyProperties.DIGEST_SHA384,KeyProperties.DIGEST_SHA512)
                .setCertificateSubject(new X500Principal(name)).setCertificateSerialNumber(BigInteger.ONE).setCertificateNotBefore(new Date(System.currentTimeMillis()-DAY)).setCertificateNotAfter(new Date(System.currentTimeMillis()+3650*DAY)).build());g.generateKeyPair();
        }
        return new KeyPair(k.getCertificate(alias).getPublicKey(),(PrivateKey)k.getKey(alias,null));
    }
    static synchronized X509Certificate root(Context c)throws Exception{
        if(ca!=null)return ca;KeyStore k=store();KeyPair root=key(k,ROOT,"CN=Thor Web Ops CA");File file=new File(c.getFilesDir(),"web-ops-ca.crt");
        if(file.exists())try(FileInputStream in=new FileInputStream(file)){
            X509Certificate existing=(X509Certificate)CertificateFactory.getInstance("X.509").generateCertificate(in);existing.verify(root.getPublic());existing.checkValidity();if(Arrays.equals(existing.getPublicKey().getEncoded(),root.getPublic().getEncoded())){ca=existing;return ca;}
        }
        String id=c.getSharedPreferences("web_ops",0).getString("certificate_id","");if(id.isEmpty()){id=UUID.randomUUID().toString().substring(0,8);c.getSharedPreferences("web_ops",0).edit().putString("certificate_id",id).commit();}
        X500Name name=new X500Name("CN=Thor Web Ops "+id+",O=Thor Companion");
        X509Certificate cert=issue(name,name,root.getPublic(),root.getPrivate(),true,Collections.emptyList(),3650*DAY);
        try(FileOutputStream out=new FileOutputStream(file)){out.write(cert.getEncoded());out.getFD().sync();}ca=cert;return ca;
    }
    private static X509Certificate issue(X500Name issuer,X500Name subject,PublicKey publicKey,PrivateKey signer,boolean root,List<String> names,long validity)throws Exception{
        AlgorithmIdentifier algorithm=new AlgorithmIdentifier(X9ObjectIdentifiers.ecdsa_with_SHA256);
        V3TBSCertificateGenerator gen=new V3TBSCertificateGenerator();gen.setSerialNumber(new ASN1Integer(new BigInteger(128,new SecureRandom()).add(BigInteger.ONE)));gen.setSignature(algorithm);gen.setIssuer(issuer);gen.setSubject(subject);
        gen.setStartDate(new Time(new Date(System.currentTimeMillis()-DAY)));gen.setEndDate(new Time(new Date(System.currentTimeMillis()+validity)));gen.setSubjectPublicKeyInfo(SubjectPublicKeyInfo.getInstance(publicKey.getEncoded()));
        ExtensionsGenerator ext=new ExtensionsGenerator();ext.addExtension(org.bouncycastle.asn1.x509.Extension.basicConstraints,true,root?new BasicConstraints(0):new BasicConstraints(false));
        ext.addExtension(org.bouncycastle.asn1.x509.Extension.keyUsage,true,new KeyUsage(root?KeyUsage.keyCertSign|KeyUsage.cRLSign:KeyUsage.digitalSignature));
        ext.addExtension(org.bouncycastle.asn1.x509.Extension.subjectKeyIdentifier,false,new SubjectKeyIdentifier(MessageDigest.getInstance("SHA-1").digest(SubjectPublicKeyInfo.getInstance(publicKey.getEncoded()).getPublicKeyData().getBytes())));
        if(!root){
            ext.addExtension(org.bouncycastle.asn1.x509.Extension.extendedKeyUsage,false,new ExtendedKeyUsage(KeyPurposeId.id_kp_serverAuth));
            ArrayList<GeneralName> san=new ArrayList<>();san.add(new GeneralName(GeneralName.dNSName,"localhost"));for(String address:names)san.add(new GeneralName(GeneralName.iPAddress,address));ext.addExtension(org.bouncycastle.asn1.x509.Extension.subjectAlternativeName,false,new GeneralNames(san.toArray(new GeneralName[0])));
        }
        gen.setExtensions(ext.generate());TBSCertificate tbs=gen.generateTBSCertificate();Signature signature=Signature.getInstance("SHA256withECDSA");signature.initSign(signer);signature.update(tbs.getEncoded("DER"));
        byte[] encoded=new DERSequence(new ASN1Encodable[]{tbs,algorithm,new DERBitString(signature.sign())}).getEncoded("DER");return (X509Certificate)CertificateFactory.getInstance("X.509").generateCertificate(new ByteArrayInputStream(encoded));
    }
    static synchronized SSLContext context(Context c,List<String> addresses)throws Exception{
        X509Certificate root=root(c);KeyStore k=store();KeyPair pair=key(k,LEAF,"CN=Thor Web Ops");
        final X509Certificate leaf=issue(X500Name.getInstance(root.getSubjectX500Principal().getEncoded()),new X500Name("CN=Thor Web Ops"),pair.getPublic(),(PrivateKey)k.getKey(ROOT,null),false,addresses,30*DAY);
        leaf.verify(root.getPublicKey());final PrivateKey privateKey=pair.getPrivate();final X509Certificate[] chain={leaf,root};
        X509ExtendedKeyManager manager=new X509ExtendedKeyManager(){
            public String[] getClientAliases(String t,Principal[] i){return null;}public String chooseClientAlias(String[] t,Principal[] i,Socket s){return null;}
            public String[] getServerAliases(String t,Principal[] i){return "EC".equals(t)?new String[]{"web"}:null;}public String chooseServerAlias(String t,Principal[] i,Socket s){return "EC".equals(t)?"web":null;}
            public String chooseEngineServerAlias(String t,Principal[] i,SSLEngine e){return "EC".equals(t)?"web":null;}public X509Certificate[] getCertificateChain(String a){return chain.clone();}public PrivateKey getPrivateKey(String a){return privateKey;}
        };
        SSLContext tls=SSLContext.getInstance("TLS");tls.init(new KeyManager[]{manager},null,new SecureRandom());return tls;
    }
    static boolean privateAddress(InetAddress a){byte[] b=a.getAddress();if(a.isLoopbackAddress())return true;if(b.length==16)return (b[0]&0xfe)==0xfc;int x=b[0]&255,y=b[1]&255;return x==10||x==172&&y>=16&&y<=31||x==192&&y==168||x==100&&y>=64&&y<=127;}
    static List<String> addresses()throws Exception{
        TreeSet<String> list=new TreeSet<>();list.add("127.0.0.1");Enumeration<NetworkInterface> interfaces=NetworkInterface.getNetworkInterfaces();while(interfaces.hasMoreElements()){
            NetworkInterface n=interfaces.nextElement();if(!n.isUp())continue;Enumeration<InetAddress> ips=n.getInetAddresses();while(ips.hasMoreElements()){InetAddress a=ips.nextElement();if(privateAddress(a)&&!a.isLinkLocalAddress())list.add(a.getHostAddress().split("%")[0]);}
        }return new ArrayList<>(list);
    }
    static String fingerprint(Context c)throws Exception{return FileAccess.hex(MessageDigest.getInstance("SHA-256").digest(root(c).getEncoded()));}
}
