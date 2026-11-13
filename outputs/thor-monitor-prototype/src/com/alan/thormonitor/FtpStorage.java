package com.alan.thormonitor;

import org.apache.ftpserver.ftplet.*;
import java.io.*;
import java.util.*;
import java.util.function.Supplier;

/** Virtual storage roots; never exposes the Android filesystem or follows links outside a grant. */
final class FtpStorage implements FileSystemView {
    private final Supplier<Map<String,File>> roots;
    private String working="/";
    FtpStorage(Supplier<Map<String,File>> roots){this.roots=roots;}
    static String normalize(String working,String input){
        if(input==null||input.length()>4096||input.indexOf('\\')>=0||input.indexOf('\0')>=0||input.indexOf('\r')>=0||input.indexOf('\n')>=0)throw new IllegalArgumentException("Invalid path");
        String full=input.startsWith("/")?input:working+"/"+input;
        ArrayDeque<String> parts=new ArrayDeque<>();
        for(String p:full.split("/")){if(p.isEmpty()||p.equals("."))continue;if(p.equals("..")){if(parts.isEmpty())throw new IllegalArgumentException("Outside shared storage");parts.removeLast();}else{if(p.length()>240)throw new IllegalArgumentException("Name too long");parts.add(p);}}
        return "/"+String.join("/",parts);
    }
    static File resolve(File root,String relative)throws IOException{
        File base=root.getCanonicalFile(),file=new File(base,relative).getCanonicalFile();
        if(!file.equals(base)&&!file.getPath().startsWith(base.getPath()+File.separator))throw new IOException("Outside shared storage");
        String rel=file.equals(base)?"":file.getPath().substring(base.getPath().length()+1);
        String lower=rel.toLowerCase(Locale.ROOT);
        if(lower.equals("android/data")||lower.startsWith("android/data/")||lower.equals("android/obb")||lower.startsWith("android/obb/"))throw new IOException("Android protects these files");
        return file;
    }
    public FtpFile getHomeDirectory(){return new Entry("/");}
    public FtpFile getWorkingDirectory(){return new Entry(working);}
    public boolean changeWorkingDirectory(String dir)throws FtpException{FtpFile f=getFile(dir);if(!f.isDirectory()||!f.isReadable())return false;working=f.getAbsolutePath();return true;}
    public FtpFile getFile(String name)throws FtpException{try{return new Entry(normalize(working,name));}catch(Exception e){throw new FtpException("Invalid shared-storage path");}}
    public boolean isRandomAccessible(){return true;}
    public void dispose(){}
    final class Entry implements FtpFile {
        final String path;
        Entry(String path){this.path=path;}
        boolean virtual(){return path.equals("/");}
        boolean storageRoot(){return !virtual()&&path.indexOf('/',1)<0;}
        File file()throws IOException{
            if(virtual())throw new IOException("Choose Internal or microSD");
            int split=path.indexOf('/',1);String root=split<0?path.substring(1):path.substring(1,split);
            File base=roots.get().get(root);if(base==null)throw new IOException("Storage unavailable or permission revoked");
            return resolve(base,split<0?"":path.substring(split+1));
        }
        public String getAbsolutePath(){return path;}
        public String getName(){return virtual()?"/":path.substring(path.lastIndexOf('/')+1);}
        public boolean isHidden(){return getName().startsWith(".");}
        public boolean isDirectory(){try{return virtual()||file().isDirectory();}catch(Exception e){return false;}}
        public boolean isFile(){try{return !virtual()&&file().isFile();}catch(Exception e){return false;}}
        public boolean doesExist(){try{return virtual()||file().exists();}catch(Exception e){return false;}}
        public boolean isReadable(){try{return virtual()||file().canRead();}catch(Exception e){return false;}}
        public boolean isWritable(){try{if(virtual())return false;File f=file();return f.exists()?f.canWrite():f.getParentFile().canWrite();}catch(Exception e){return false;}}
        public boolean isRemovable(){return !virtual()&&!storageRoot()&&isWritable();}
        public String getOwnerName(){return "thor";}
        public String getGroupName(){return "thor";}
        public int getLinkCount(){return 1;}
        public long getLastModified(){try{return virtual()?0:file().lastModified();}catch(Exception e){return 0;}}
        public boolean setLastModified(long time){try{return isRemovable()&&file().setLastModified(time);}catch(Exception e){return false;}}
        public long getSize(){try{return isDirectory()?0:file().length();}catch(Exception e){return 0;}}
        public Object getPhysicalFile(){try{return virtual()?null:file();}catch(Exception e){return null;}}
        public boolean mkdir(){try{return isWritable()&&file().mkdir();}catch(Exception e){return false;}}
        public boolean delete(){try{return isRemovable()&&file().delete();}catch(Exception e){return false;}}
        public boolean move(FtpFile target){
            try{if(!(target instanceof FtpStorage.Entry)||!isRemovable()||!target.isWritable()||target.doesExist())return false;return file().renameTo(((Entry)target).file());}catch(Exception e){return false;}
        }
        public List<FtpFile> listFiles(){
            List<FtpFile> result=new ArrayList<>();
            try{
                if(virtual()){for(String root:roots.get().keySet())result.add(new Entry("/"+root));return result;}
                File[] children=file().listFiles();if(children==null)return null;
                for(File child:children){Entry entry=new Entry(path+"/"+child.getName());try{entry.file();result.add(entry);}catch(IOException ignored){}}
                result.sort(Comparator.comparing(f->f.getName().toLowerCase(Locale.ROOT)));return result;
            }catch(Exception e){return null;}
        }
        public InputStream createInputStream(long offset)throws IOException{
            if(!isFile()||!isReadable()||offset<0||offset>getSize()||getSize()>64L*1024*1024*1024)throw new IOException("File unavailable or too large");
            RandomAccessFile input=new RandomAccessFile(file(),"r");input.seek(offset);
            return new InputStream(){public int read()throws IOException{return input.read();}public int read(byte[] b,int o,int n)throws IOException{return input.read(b,o,n);}public void close()throws IOException{input.close();}};
        }
        public OutputStream createOutputStream(long offset)throws IOException{
            if(!isWritable()||isDirectory()||offset<0||offset>getSize())throw new IOException("Folder is not writable or resume offset is invalid");
            RandomAccessFile output=new RandomAccessFile(file(),"rw");if(offset==0)output.setLength(0);output.seek(offset);
            return new OutputStream(){long written=offset;public void write(int b)throws IOException{write(new byte[]{(byte)b},0,1);}public void write(byte[] b,int o,int n)throws IOException{if(written+n>64L*1024*1024*1024)throw new IOException("File exceeds 64 GiB");output.write(b,o,n);written+=n;}public void close()throws IOException{output.close();}};
        }
    }
}
