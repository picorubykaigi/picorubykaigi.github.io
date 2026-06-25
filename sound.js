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

  // 電車の通過音(プラレール): ①転がり音「ごー」(なめらかなノイズの唸り) + ②車輪の刻み「ガタン・ゴトン」
  //   (金属的クラックを2連で規則的に=電車の正体) + ③トイモーターの唸り。音量スウェル(素早く立ち上げ→保持
  //   →長い余韻) + 穏やかなドップラー。小型スピーカーのEQ+ソフトクリップで安っぽい「チープ」な質感に。
  // dur=全体の長さ(秒) / master=音量 / peakFrac=ピーク(=通過)の位置(0..1)。
  // チープ感の調整パラメータ(必要なら window.trainTune={...} で個別に上書き可):
  //   drive=ジャリ歪み / lp=高域の蓋 / honk=中域の箱鳴り / motGain=モーター唸りの量 / motQ=唸りのピッチ感
  const TRAIN_DEFAULT={drive:5.5, lp:4400, honk:4.5, motGain:0.16, motQ:5.5};
  const trainPass=(dur=3.2,master=0.3,peakFrac=0.13,opts)=>{
    const o=Object.assign({},TRAIN_DEFAULT,window.trainTune||{},opts||{});
    const c=ac(), t0=c.currentTime+0.02, pk=t0+dur*peakFrac, end=t0+dur, hold=pk+(end-pk)*0.28;
    // 音量スウェル: 素早く立ち上げ→通過中は保持→長く減衰(余韻)
    const g=c.createGain();
    g.gain.setValueAtTime(0.0001,t0); g.gain.exponentialRampToValueAtTime(master,pk);
    g.gain.setValueAtTime(master,hold); g.gain.exponentialRampToValueAtTime(0.0001,end);
    // 小さなスピーカー感(チープ): 低域を削り、中域の箱鳴りを少し足す。高域は削りすぎない(こもらせない)。
    // さらに「安物スピーカーが歪んでジャリつく」=ソフトクリップ(アナログ的な歪み)を薄くかけて安っぽさを出す。
    // ※ビットクラッシュ(デジタル/ゲーム感)は使わない。
    const spk1=c.createBiquadFilter(); spk1.type='highpass'; spk1.frequency.value=400; spk1.Q.value=0.7; // 低域を削る=細い
    const spk2=c.createBiquadFilter(); spk2.type='lowpass';  spk2.frequency.value=o.lp; spk2.Q.value=0.7; // 高域は軽く(こもらせない)
    const spk3=c.createBiquadFilter(); spk3.type='peaking';  spk3.frequency.value=1300; spk3.Q.value=1.1; spk3.gain.value=o.honk; // 中域の箱鳴り
    const drv=c.createWaveShaper(); drv.oversample='2x';     // ソフトクリップ=安物が軽く歪むジャリ感
    const dc=new Float32Array(1024), k=o.drive; for(let i=0;i<1024;i++){ const x=i*2/1024-1; dc[i]=Math.tanh(k*x); } drv.curve=dc;
    const post=c.createGain(); post.gain.value=0.7;          // 歪みで上がった分のメイクアップ
    g.connect(spk1); spk1.connect(spk2); spk2.connect(spk3); spk3.connect(drv); drv.connect(post); post.connect(c.destination);
    // ① 転がり音「ごー」: 軽いlo-fiノイズ → 低めbandpass(穏やかドップラー) → 蓋。
    //   ※ビットクラッシュ(8bitグリット)は外した(=ゲーム音っぽさの主因)。ノイズは素直なまま機械的な唸りに。
    const n=Math.floor(c.sampleRate*dur), buf=c.createBuffer(1,n,c.sampleRate), d=buf.getChannelData(0);
    const step=Math.max(1,Math.floor(c.sampleRate/16000)); let hn=0;   // ごく軽いlo-fi
    for(let i=0;i<n;i++){ if(i%step===0) hn=Math.random()*2-1; d[i]=hn; }
    const src=c.createBufferSource(); src.buffer=buf;
    const bp=c.createBiquadFilter(); bp.type='bandpass'; bp.Q.value=0.7;
    bp.frequency.setValueAtTime(200,t0); bp.frequency.linearRampToValueAtTime(240,pk); bp.frequency.linearRampToValueAtTime(150,end);
    const cap=c.createBiquadFilter(); cap.type='lowpass'; cap.frequency.value=900; cap.Q.value=0.4;
    const nG=c.createGain(); nG.gain.value=0.4;
    src.connect(bp); bp.connect(cap); cap.connect(nG); nG.connect(g);
    src.start(t0); src.stop(end+0.02);
    // ①.5 トイモーターの唸り(機械的): ノイズを共鳴bandpass(高Q)に通して「ピッチのある唸り」にする。
    //      クリーンな合成オシレーター(=ゲーム機の楽器音)を避け、ノイズ由来のザラついた実機モーター感に。
    const msrc=c.createBufferSource(); msrc.buffer=buf;                              // 転がりと同じノイズを流用
    const mbp=c.createBiquadFilter(); mbp.type='bandpass'; mbp.Q.value=o.motQ;        // 共鳴で唸りのピッチ感(でもノイズ質感)
    mbp.frequency.setValueAtTime(300,t0); mbp.frequency.linearRampToValueAtTime(340,pk); mbp.frequency.linearRampToValueAtTime(250,end);
    const vib=c.createOscillator(); vib.type='sine'; vib.frequency.value=7;          // モーターのフラッター(共鳴周波数を揺らす)
    const vibG=c.createGain(); vibG.gain.value=22; vib.connect(vibG).connect(mbp.frequency);
    const motG=c.createGain(); motG.gain.value=o.motGain;
    msrc.connect(mbp); mbp.connect(motG); motG.connect(g);
    msrc.start(t0); msrc.stop(end+0.02); vib.start(t0); vib.stop(end+0.02);
    // ② 車輪の刻み「ガタン・ゴトン」: 金属的な短いクラックを2連(da-dum)で規則的に。g経由なので距離で増減
    const clack=(at)=>{
      const nb=Math.floor(c.sampleRate*0.04), b=c.createBuffer(1,nb,c.sampleRate), dd=b.getChannelData(0);
      for(let i=0;i<nb;i++) dd[i]=(Math.random()*2-1)*Math.pow(1-i/nb,4); // 速い減衰=コツッ
      const s=c.createBufferSource(); s.buffer=b;
      const bpf=c.createBiquadFilter(); bpf.type='bandpass'; bpf.frequency.value=1600; bpf.Q.value=3; // 金属的
      const cg=c.createGain(); cg.gain.value=0.5;
      s.connect(bpf); bpf.connect(cg); cg.connect(g); s.start(at);
    };
    for(let cyc=t0; cyc<end-0.05; cyc+=0.34){ clack(cyc); clack(cyc+0.09); } // ガタン・ゴトン の繰り返し
  };

  // ===== ダンス・グルーヴ(スピーカーを挿すと再生・抜くと停止) =====
  // 縁のマイコンボードが踊るあいだ流す、ループするチップチューン。
  // ベース(三角)＋リード(矩形アルペジオ)＋キック＋ハットを、先読みスケジューラで途切れず回す。
  let danceTimer=null, danceBus=null, danceT0=null;   // danceT0=グルーヴの拍0のAudioContext時刻(動きと共有する)
  const dkick=(c,bus,t)=>{ // バスドラ: 低いサインを素早く落とす
    const o=c.createOscillator(), g=c.createGain(); o.type='sine';
    o.frequency.setValueAtTime(150,t); o.frequency.exponentialRampToValueAtTime(48,t+0.11);
    g.gain.setValueAtTime(0.0001,t); g.gain.exponentialRampToValueAtTime(0.9,t+0.005);
    g.gain.exponentialRampToValueAtTime(0.0001,t+0.15);
    o.connect(g).connect(bus); o.start(t); o.stop(t+0.17);
  };
  // 16ステップ(8分音符)1ループ。0=休符。ベース(三角)＋リード(矩形＋軽いビブラート)。
  const D_BASS=['C2',0,'C3',0,'G1',0,'G2',0,'A1',0,'A2',0,'F1',0,'G1',0];
  const D_LEAD=['E5','G5','C6','G5','E5','G5','D6','B5','C6','E6','C6','A5','F5','A5','G5','B5'];
  const DANCE_MASTER=0.02;          // マスター音量
  const danceStart=bpm=>{
    bpm=bpm||144;
    if(danceTimer) return;            // 多重起動を防ぐ(socket は毎フレーム apply するため)
    const c=ac();
    const step=(60/bpm)/2, STEPS=16, loopDur=STEPS*step;
    const bus=c.createGain(); bus.gain.value=0.0001; bus.connect(c.destination);
    bus.gain.exponentialRampToValueAtTime(DANCE_MASTER, c.currentTime+0.2);   // そっとフェードイン
    danceBus=bus;
    danceT0=c.currentTime+0.1;        // 拍0の時刻(動き側 danceClock と共有)
    let nextT=danceT0;
    const tick=()=>{
      const t0=nextT;
      for(let i=0;i<STEPS;i++){ const t=t0+i*step;
        const b=D_BASS[i]; if(b) blip(c,bus,fM(midiOf(b)),t,step*1.6,0.5,'triangle');         // ベース(三角)
        const l=D_LEAD[i]; if(l) blip(c,bus,fM(midiOf(l)),t,step*0.92,0.34,'square',0.008);   // リード(矩形＋軽いビブラート)
        if(i%4===0) dkick(c,bus,t);                                                          // 4つ打ちキック
        if(i%2===1) sparkle(c,bus,t,0.022,0.10);                                             // ハット(裏)
        if(i===4||i===12) sparkle(c,bus,t,0.055,0.18);                                       // スネア風
      }
      nextT+=loopDur;
      danceTimer=setTimeout(tick, loopDur*1000-55);   // 1ループぶん先読みして繋ぐ
    };
    danceTimer=setTimeout(tick,0);   // ガード成立用に timer をセット → tick が自分で次を予約
  };
  const danceStop=()=>{
    if(!danceTimer) return; clearTimeout(danceTimer); danceTimer=null; danceT0=null;
    const g=danceBus; danceBus=null; if(!g) return;
    try{ const c=ac(), n=c.currentTime;
      g.gain.cancelScheduledValues(n); g.gain.setValueAtTime(Math.max(g.gain.value,0.0001),n);
      g.gain.exponentialRampToValueAtTime(0.0001,n+0.22);                 // すっと止める
    }catch(e){}
    setTimeout(()=>{ try{g.disconnect();}catch(e){} },450);
  };

  global.playPico=playPico;
  global.trainPass=trainPass;   // 電車の通過音(プラレール演出から呼ぶ)
  global.danceStart=danceStart; // ダンスのグルーヴ開始(スピーカー挿入)
  global.danceStop=danceStop;   // ダンスのグルーヴ停止(スピーカー抜去)
  // グルーヴの拍0からの経過秒(再生中のみ)。動き側がこれを読んで同じ時計で拍を刻む
  global.danceClock=()=> danceT0!=null ? Math.max(0, ac().currentTime - danceT0) : null;
  global.audioCtx=ac;   // ページ共通の AudioContext を公開(全効果音で共有)

  // 初回のユーザー操作で AudioContext を解錠する(autoplay制限で suspended のままを防ぐ)
  const GEST=['pointerdown','mousedown','touchstart','keydown','click'];
  const unlock=()=>{ try{ ac(); }catch(e){}   // 生成＋resume(無音バッファは使わない=device error回避)
    GEST.forEach(t=>global.removeEventListener(t,unlock,true)); };
  GEST.forEach(t=>global.addEventListener(t,unlock,true));
})(window);
