import {Input,UrlSource,MP4,CanvasSink,Output,Mp4OutputFormat,CanvasSource,Quality,EncodedPacketSink,EncodedAudioPacketSource,EncodedPacket,BufferTarget,StreamTarget,canEncodeVideo} from './vendor/mediabunny.mjs';

/** Draw decoded frames at the selected timeline; preserve one game-audio track. */
export async function exportVideo({token,tracks,mode,fps,quality,fileHandle,signal,onProgress}) {
    if(!globalThis.VideoEncoder||!globalThis.VideoDecoder)throw new Error('This browser cannot export video. Use a current Chrome, Edge or Safari, or download the original videos.');
    if(!await canEncodeVideo('avc'))throw new Error('This browser cannot encode MP4 video. Download the originals or use a current Chrome, Edge or Safari.');
    const inputs=[],iterators=[];let output=null,writable=null,wake=null;
    const abort=()=>{for(const input of inputs)input.dispose();};signal?.addEventListener('abort',abort,{once:true});
    try {
        try{wake=await navigator.wakeLock?.request('screen');}catch{}
        const selected=tracks.filter(t=>mode===2||t.screen===mode).sort((a,b)=>a.screen-b.screen);if(!selected.length)throw new Error('Recording tracks are unavailable');
        const firstOffset=Math.min(...selected.map(t=>t.offset_ms||0));
        for(const track of selected) {
            signal?.throwIfAborted();const source=new UrlSource(`/api/record/file?token=${encodeURIComponent(token)}&screen=${track.screen}`,{requestInit:{credentials:'same-origin',cache:'no-store'},maxCacheSize:24*1024*1024,maxParallelRequests:1,getRetryDelay:attempt=>attempt<3?300*(attempt+1):null});
            const input=new Input({source,formats:[MP4]});inputs.push(input);
            const video=await input.getPrimaryVideoTrack();if(!video||!await video.canDecode())throw new Error('This browser cannot decode the recording. Download the originals instead.');
            track.input=input;track.video=video;track.first=await video.getFirstTimestamp();track.duration=await video.computeDuration();track.offset=((track.offset_ms||0)-firstOffset)/1000;
        }
        const scale=quality===1?1:Math.min(1,1280/Math.max(...selected.map(t=>t.video.displayWidth)));
        const width=Math.ceil(Math.max(...selected.map(t=>t.video.displayWidth))*scale/2)*2,height=selected.reduce((n,t)=>n+Math.ceil(t.video.displayHeight*scale/2)*2,0);
        const bitrate=quality===1?(mode===2?24000000:16000000):(mode===2?10000000:7000000),encoding={codec:'avc',quality:new Quality({bitrate}),hardwareAcceleration:'prefer-hardware'};
        if(!await canEncodeVideo('avc',{width,height,frameRate:fps,...encoding}))throw new Error('The selected size or frame rate is unsupported. Try Standard quality or 30 fps.');
        const canvas=document.createElement('canvas');canvas.width=width;canvas.height=height;const context=canvas.getContext('2d',{alpha:false});
        let target;if(fileHandle){writable=await fileHandle.createWritable();target=new StreamTarget(new WritableStream({write:chunk=>writable.write(chunk)}),{chunked:true,chunkSize:1024*1024});}else target=new BufferTarget();
        output=new Output({format:new Mp4OutputFormat({fastStart:false}),target});const videoSource=new CanvasSource(canvas,encoding);output.addVideoTrack(videoSource,{frameRate:fps});
        let audio=null,audioSource=null;for(const track of selected){const a=await track.input.getPrimaryAudioTrack();if(a?.codec==='aac'){audio={track,a};audioSource=new EncodedAudioPacketSource('aac');output.addAudioTrack(audioSource);break;}}
        const duration=Math.max(...selected.map(t=>t.offset+t.duration-t.first));if(!Number.isFinite(duration)||duration<=0||duration>191)throw new Error('Invalid recording duration');
        // Avoid unbounded in-memory outputs on browsers without direct-to-file support.
        if(!fileHandle&&duration*bitrate/8>384*1024*1024)throw new Error('This export needs direct file saving. Use Chrome or Edge on a computer, or choose Standard quality.');
        for(const track of selected){const sink=new CanvasSink(track.video,{poolSize:2});function* timestamps(){for(let frame=0;frame<Math.ceil(duration*fps);frame++)yield Math.max(track.first,track.first+frame/fps-track.offset);}track.frames=sink.canvasesAtTimestamps(timestamps());iterators.push(track.frames);}
        await output.start();
        const audioJob=(async()=>{if(!audioSource)return;let first=true;const decoderConfig=await audio.a.getDecoderConfig(),sink=new EncodedPacketSink(audio.a);for await(const packet of sink.packets()){signal?.throwIfAborted();const timestamp=packet.timestamp-audio.track.first+audio.track.offset;if(timestamp+packet.duration<=0||timestamp>=duration)continue;const adjusted=new EncodedPacket(packet.data,packet.type,Math.max(0,timestamp),packet.duration,packet.sequenceNumber,undefined,packet.sideData);await audioSource.add(adjusted,first?{decoderConfig}:undefined);first=false;}audioSource.close();})();
        const videoJob=(async()=>{const count=Math.ceil(duration*fps);for(let frame=0;frame<count;frame++){signal?.throwIfAborted();const t=frame/fps;context.fillStyle='#000';context.fillRect(0,0,width,height);let y=0;const frames=await Promise.all(selected.map(track=>track.frames.next()));for(let i=0;i<selected.length;i++){const track=selected[i],h=Math.ceil(track.video.displayHeight*scale/2)*2,w=Math.ceil(track.video.displayWidth*scale/2)*2;if(t>=track.offset&&frames[i].value)context.drawImage(frames[i].value.canvas,(width-w)/2,y,w,h);y+=h;}await videoSource.add(t,1/fps);if(frame%fps===0)onProgress(`Exporting · ${Math.round(frame/count*100)}%`);}videoSource.close();})();
        try{await Promise.all([audioJob,videoJob]);}catch(error){abort();await output.cancel().catch(()=>{});await Promise.allSettled([audioJob,videoJob]);throw error;}
        signal?.throwIfAborted();onProgress('Finalizing MP4…');await output.finalize();
        if(writable){await writable.close();writable=null;onProgress('Video saved');return null;}
        onProgress('Video ready');return new Blob([target.buffer],{type:'video/mp4'});
    }catch(error){if(output)await output.cancel().catch(()=>{});if(writable)await writable.abort().catch(()=>{});throw error;}finally{signal?.removeEventListener('abort',abort);for(const iterator of iterators)await iterator.return().catch(()=>{});for(const input of inputs)input.dispose();await wake?.release().catch(()=>{});}
}
