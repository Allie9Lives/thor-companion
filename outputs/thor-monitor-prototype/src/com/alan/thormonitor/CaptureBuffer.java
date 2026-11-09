package com.alan.thormonitor;

import java.nio.ByteBuffer;
import java.util.zip.CRC32;

/** One bounded, ephemeral capture. Kept only until delivery, cancel, or timeout. */
final class CaptureBuffer {
    final byte[] bytes;
    final int token;
    final long crc;
    CaptureBuffer(byte[] bytes,int token) {
        if(bytes==null || bytes.length<10 || bytes.length>ScreenCapture.MAX_BYTES)throw new IllegalArgumentException("Invalid capture size");
        this.bytes=bytes;this.token=token;CRC32 crc=new CRC32();crc.update(bytes);this.crc=crc.getValue();
    }
    byte[] packet(int offset,int mtu) {
        if(offset<0 || offset>=bytes.length || mtu<40)throw new IllegalArgumentException("Invalid screenshot packet");
        int count=Math.min(bytes.length-offset,Math.min(mtu-3-16,480));
        return ByteBuffer.allocate(16+count).put(new byte[]{'T','S','0','1'}).putInt(token).putInt(offset).putInt(bytes.length).put(bytes,offset,count).array();
    }
}
