/** Resumable, bounded-memory downloads. Never changes certificate validation. */
export async function downloadFile({url,statUrl,name,request,onProgress,signal}) {
    let handle=null,writable=null;
    try {
        if('showSaveFilePicker' in window&&window.isSecureContext) {
            try { handle=await window.showSaveFilePicker({suggestedName:name}); }
            catch(error) { if(error.name==='AbortError')return;if(error.name!=='SecurityError')throw error; }
        }
        signal?.throwIfAborted();const stat=await request(statUrl);signal?.throwIfAborted();
        if(!Number.isSafeInteger(stat.size)||stat.size<0)throw new Error('File size is unavailable');
        if(!handle&&stat.size>256*1024*1024) {
            const link=document.createElement('a');link.href=url;link.download=name;document.body.append(link);link.click();link.remove();
            onProgress('Download handed to your browser. If it fails, trust the Thor certificate and retry.');return;
        }
        signal?.throwIfAborted();if(handle)writable=await handle.createWritable();
        const pieces=[];const chunkSize=4*1024*1024;
        for(let position=0;position<stat.size;) {
            signal?.throwIfAborted();let piece=null;const end=Math.min(stat.size,position+chunkSize)-1;
            for(let attempt=0;attempt<4;attempt++) {
                try {
                    const response=await fetch(url,{credentials:'same-origin',cache:'no-store',headers:{Range:`bytes=${position}-${end}`,'If-Range':stat.etag},signal});
                    if(response.status===401)throw new Error('Your session expired. Sign in and download again.');
                    if(response.status!==206) { await response.body?.cancel();throw new Error(response.status===409?'Another transfer is busy. Try again shortly.':'The file changed or the server could not resume it. Start again.'); }
                    if(response.headers.get('ETag')!==stat.etag)throw new Error('The file changed. Start the download again.');
                    piece=new Uint8Array(await response.arrayBuffer());if(piece.length!==end-position+1)throw new Error('Transfer interrupted');break;
                } catch(error) {
                    signal?.throwIfAborted();if(attempt===3||error.message.includes('session expired')||error.message.includes('file changed'))throw error;
                    onProgress(`Connection interrupted · retrying ${attempt+1}/3`);await new Promise(resolve=>setTimeout(resolve,300*(attempt+1)**2));
                }
            }
            if(writable)await writable.write(piece);else pieces.push(piece);
            position=end+1;onProgress(`${name} · ${Math.round(position/stat.size*100)}%`);
        }
        signal?.throwIfAborted();if(writable){await writable.close();writable=null;}else{const url=URL.createObjectURL(new Blob(pieces,{type:'application/octet-stream'})),link=document.createElement('a');link.href=url;link.download=name;document.body.append(link);link.click();link.remove();setTimeout(()=>URL.revokeObjectURL(url),60000);}
        onProgress(`${name} · downloaded`);
    }catch(error){if(writable)await writable.abort().catch(()=>{});if(error.name==='AbortError')onProgress('Download cancelled');else throw error;}
}
