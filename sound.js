(function(global){
  let ctx=null;
  const make=()=>{
    const c=new (global.AudioContext||global.webkitAudioContext)();
    // デバイス/レンダラのエラー時は破棄 → 次回 ac() で作り直す(オーディオサービス復帰に追従)
    try{ c.onerror=()=>{ try{c.close();}catch(_){}; if(ctx===c) ctx=null; }; }catch(_){}
    return c;
  };
  const ac=()=>{ // AudioContext は遅延生成し、壊れていれば作り直し、サスペンドなら再開する
    if(!ctx || ctx.state==='closed') ctx=make();
    if(ctx.state==='suspended') ctx.resume();
    return ctx;
  };

  // 音名 -> MIDI -> 周波数
  const SEMI={C:0,'C#':1,Db:1,D:2,'D#':3,Eb:3,E:4,F:5,'F#':6,Gb:6,G:7,'G#':8,Ab:8,A:9,'A#':10,Bb:10,B:11};
  const midiOf=n=>{const m=/^([A-G][#b]?)(\d)$/.exec(n);return (+m[2]+1)*12+SEMI[m[1]];};
  const fM=m=>440*Math.pow(2,(m-69)/12);

  // 1音: パッと立ち上げてスッと減衰 = チップチューンの粒立ち
  const blip=(c,bus,f,t0,dur,vol,type,vib)=>{
    if(!f) return;
    const o=c.createOscillator(); o.type=type||'square'; o.frequency.setValueAtTime(f,t0);
    if(vib){ // 軽いビブラートで「歌う」感じ
      const lfo=c.createOscillator(), lg=c.createGain();
      lfo.frequency.value=6.5; lg.gain.value=f*vib;
      lfo.connect(lg).connect(o.frequency); lfo.start(t0); lfo.stop(t0+dur+0.05);
    }
    const g=c.createGain(), a=0.006, end=t0+dur;
    g.gain.setValueAtTime(0,t0);
    g.gain.linearRampToValueAtTime(vol,t0+a);
    g.gain.exponentialRampToValueAtTime(vol*0.6,t0+dur*0.5);
    g.gain.exponentialRampToValueAtTime(0.0001,end);
    o.connect(g).connect(bus); o.start(t0); o.stop(end+0.02);
  };

  // パーカッシブなきらめき: ホワイトノイズの短いバースト
  const sparkle=(c,bus,t0,dur,vol)=>{
    const n=Math.floor(c.sampleRate*dur), buf=c.createBuffer(1,n,c.sampleRate), d=buf.getChannelData(0);
    for(let i=0;i<n;i++) d[i]=(Math.random()*2-1)*Math.pow(1-i/n,2); // 減衰ノイズ
    const src=c.createBufferSource(); src.buffer=buf;
    const hp=c.createBiquadFilter(); hp.type='highpass'; hp.frequency.value=4000;
    const g=c.createGain(); g.gain.value=vol;
    src.connect(hp).connect(g).connect(bus); src.start(t0);
  };

  // notes を鳴らす(軽いマスター音量)
  const render=(notes,master=0.2)=>{
    const c=ac(), t0=c.currentTime+0.04;
    const bus=c.createGain(); bus.gain.value=master; bus.connect(c.destination);
    notes.forEach(nt=>{
      if(nt.noise){ sparkle(c,bus,t0+nt.t,nt.dur,nt.vol); return; }
      blip(c,bus,nt.f,t0+nt.t,nt.dur,nt.vol,nt.type,nt.vib);
    });
  };

  // 確定メロディ: 下って上がる7音 / 和声 C-F-C
  const MEL=[['C7',0.00,0.15,'C'],['G6',0.16,0.15,'C'],
             ['A6',0.32,0.15,'F'],['F6',0.48,0.15,'F'],
             ['G6',0.64,0.15,'C'],['A6',0.80,0.15,'F'],['C7',0.96,0.50,'C']];
  // 和音の構成音/根音(下声・ベースを協和させる)
  const CHPC={C:[0,4,7],F:[5,9,0]}, ROOTPC={C:0,F:5};
  const snapTo=(target,pcs)=>{let best=0,bd=1e9;pcs.forEach(pc=>{for(let m=pc;m<120;m+=12){const d=Math.abs(m-target);if(d<bd){bd=d;best=m;}}});return best;};
  const nearBass=(pc,center)=>{let best=0,bd=1e9;for(let m=pc;m<120;m+=12){const d=Math.abs(m-center);if(d<bd){bd=d;best=m;}}return best;};

  // 確定音色: スタッカートのノコギリ2声 + 三角ベース + 末尾にきらめき。末尾だけ伸ばす。
  const STAC=0.08, LAST=0.40, VIB=0.01, N=MEL.length;
  const playPico=()=>{
    const notes=[]; let last=null;
    MEL.forEach(([n,t,,ch],i)=>{
      const um=midiOf(n), isLast=i===N-1, md=isLast?LAST:STAC;
      notes.push({f:fM(um),t,dur:md,type:'sawtooth',vol:0.55,vib:VIB});                    // 上声
      notes.push({f:fM(snapTo(um-8,CHPC[ch])),t,dur:md,type:'square',vol:0.40,vib:VIB*0.5}); // 下声(約6度下)
      if(ch!==last){ // 和音が変わったらベースを置く
        let end=MEL[N-1][1]+LAST, trailing=true;
        for(let j=i+1;j<N;j++){ if(MEL[j][3]!==ch){ end=MEL[j][1]; trailing=false; break; } }
        const bd=trailing?end-t:Math.min(end-t,STAC+0.10); // 末尾は伸ばし、途中はスタッカート
        notes.push({f:fM(nearBass(ROOTPC[ch],55)),t,dur:bd,type:'triangle',vol:0.28});
        last=ch;
      }
    });
    notes.push({noise:true,t:MEL[N-1][1],dur:0.14,vol:0.22}); // 着地のきらめき
    render(notes,0.2);
  };

  global.playPico=playPico;
  global.audioCtx=ac;   // ページ共通の AudioContext を公開(全効果音で共有)

  // 初回のユーザー操作で AudioContext を解錠する(autoplay制限で suspended のままを防ぐ)
  const GEST=['pointerdown','mousedown','touchstart','keydown','click'];
  const unlock=()=>{ try{ ac(); }catch(e){}   // 生成＋resume(無音バッファは使わない=device error回避)
    GEST.forEach(t=>global.removeEventListener(t,unlock,true)); };
  GEST.forEach(t=>global.addEventListener(t,unlock,true));
})(window);
