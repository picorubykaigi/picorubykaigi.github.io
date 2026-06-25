(function(global){
  let ctx=null, gestured=false;   // gestured=ユーザー操作を一度でも受け取ったか
  const make=()=>{
    const c=new (global.AudioContext||global.webkitAudioContext)();
    // デバイス/レンダラのエラー時は破棄 → 次回 ac() で作り直す(オーディオサービス復帰に追従)
    try{ c.onerror=()=>{ try{c.close();}catch(_){}; if(ctx===c) ctx=null; }; }catch(_){}
    return c;
  };
  const ac=()=>{ // AudioContext は遅延生成し、壊れていれば作り直し、サスペンドなら再開する
    // ユーザー操作前は生成も resume もしない。リロードでパーティモードが復元され、
    // frame ループが毎フレーム danceStart/danceParty を呼んでも autoplay 警告を出さないため。
    if(!gestured) return null;
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
    const c=ac(); if(!c) return;      // 操作前は鳴らさない(autoplay制限)
    const t0=c.currentTime+0.04;
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
    const c=ac(); if(!c) return;      // 操作前は鳴らさない(autoplay制限)
    const t0=c.currentTime+0.02, pk=t0+dur*peakFrac, end=t0+dur, hold=pk+(end-pk)*0.28;
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
  let danceBassBus=null, danceBassEQ=null, danceThumpBus=null, dancePartyOn=false; // ベース専用バス(パーティモードで増強)/thumpゲート
  let danceFirstBass=false;          // 再生開始後の最初のベース1音だけ弱める用のワンショット
  let danceLatched=false;            // 4小節後の自動終了ラッチ。立っている間は danceStart しても再開しない(抜くと解除)
  const dkick=(c,bus,t)=>{ // バスドラ: 低いサインを素早く落とす
    const o=c.createOscillator(), g=c.createGain(); o.type='sine';
    o.frequency.setValueAtTime(150,t); o.frequency.exponentialRampToValueAtTime(48,t+0.11);
    g.gain.setValueAtTime(0.0001,t); g.gain.exponentialRampToValueAtTime(0.9,t+0.005);
    g.gain.exponentialRampToValueAtTime(0.0001,t+0.15);
    o.connect(g).connect(bus); o.start(t); o.stop(t+0.17);
  };
  // パーティ用クラップ「パンッ」: 短いノイズを数回ずらして重ねる=手拍子のばらけた厚み
  const dclap=(c,bus,t)=>{
    [0,0.011,0.022].forEach((d,k)=>{
      const n=Math.floor(c.sampleRate*0.05), b=c.createBuffer(1,n,c.sampleRate), dd=b.getChannelData(0);
      for(let i=0;i<n;i++) dd[i]=(Math.random()*2-1)*Math.pow(1-i/n,3);   // 速い減衰
      const s=c.createBufferSource(); s.buffer=b;
      const bp=c.createBiquadFilter(); bp.type='bandpass'; bp.frequency.value=1600; bp.Q.value=1.2; // 手拍子の帯域
      const g=c.createGain(); g.gain.value=(k===2)?0.5:0.3;              // 本体を少し強く
      s.connect(bp).connect(g).connect(bus); s.start(t+d);
    });
  };
  // パーティ用の太いサブベース: サインの基音に tanh 歪みで芯(倍音)を足して
  //   小型スピーカーでも“太く”聞こえるようにする。ピッチは動かさない。
  const WS_CURVE=(()=>{ const cv=new Float32Array(1024); for(let i=0;i<1024;i++){ const x=i*2/1024-1; cv[i]=Math.tanh(2.4*x); } return cv; })();
  const dthump=(c,bus,f,t,dur,vol)=>{
    const v=vol||1;                                                                    // 音量倍率(後拍の強調などに使う)
    const o=c.createOscillator(); o.type='sine'; o.frequency.setValueAtTime(f,t);     // ピッチ固定=芯のある低音
    const drive=c.createWaveShaper(); drive.curve=WS_CURVE; drive.oversample='2x';     // 倍音=太さ/芯
    const g=c.createGain();
    g.gain.setValueAtTime(0.0001,t);
    g.gain.exponentialRampToValueAtTime(v,t+0.006);                                    // ドンッ(より速い立ち上げ)
    g.gain.setValueAtTime(v,t+dur*0.5);                                                // ずん…(保持で重み)
    g.gain.exponentialRampToValueAtTime(0.0001,t+dur);                                 // スッと抜ける
    o.connect(drive).connect(g).connect(bus); o.start(t); o.stop(t+dur+0.02);
    // アタックのクリック(芯/パンチ): ごく短い高めのトランジェントで「どんっ」の打感を立てる
    const ck=c.createOscillator(); ck.type='triangle'; ck.frequency.setValueAtTime(f*4,t);
    const cg=c.createGain(); cg.gain.setValueAtTime(0.5*v,t); cg.gain.exponentialRampToValueAtTime(0.0001,t+0.035);
    ck.connect(cg).connect(bus); ck.start(t); ck.stop(t+0.05);
  };
  // 16ステップ(8分音符)1ループ。0=休符。ベース(三角)＋リード(矩形＋軽いビブラート)。
  const D_BASS=['C2',0,'C3',0,'G1',0,'G2',0,'A1',0,'A2',0,'F1',0,'G1',0];
  const D_LEAD=['E5','G5','C6','G5','E5','G5','D6','B5','C6','E6','C6','A5','F5','A5','G5','B5'];
  const DANCE_MASTER=0.02;          // マスター音量(ライト)
  const DANCE_MASTER_PARTY=0.016;   // パーティモード時は要素が増え密度が上がるぶん、総音量をライトモードに合わせて少し下げる
  const BASS_PARTY_GAIN=2.2;        // パーティモード時のベース音量倍率(通常=1)
  const BASS_PARTY_EQ=8;            // パーティモード時の低域シェルフブースト(dB / 通常=0)
  const danceStart=bpm=>{
    bpm=bpm||144;
    if(danceTimer||danceLatched) return;  // 多重起動を防ぐ(socket は毎フレーム apply するため)。自動終了後は抜くまで再開しない
    const c=ac(); if(!c) return;      // 操作前は鳴らさない(操作後、frame の再呼び出しで自然に開始する)
    const step=(60/bpm)/2, STEPS=16, loopDur=STEPS*step;
    const bus=c.createGain(); bus.gain.value=0.0001; bus.connect(c.destination);
    bus.gain.exponentialRampToValueAtTime(dancePartyOn?DANCE_MASTER_PARTY:DANCE_MASTER, c.currentTime+0.2);   // そっとフェードイン(開始時のモードに合わせる)
    danceBus=bus;
    // ベースだけ別バスに通す: パーティモードで gain と低域シェルフを持ち上げてベースを強くする
    const bassEQ=c.createBiquadFilter(); bassEQ.type='lowshelf'; bassEQ.frequency.value=160;
    const bassBus=c.createGain();
    bassEQ.connect(bassBus); bassBus.connect(bus);
    danceBassEQ=bassEQ; danceBassBus=bassBus;
    bassEQ.gain.value=dancePartyOn?BASS_PARTY_EQ:0;       // 再生開始時点のパーティ状態を反映
    bassBus.gain.value=dancePartyOn?BASS_PARTY_GAIN:1;
    // thumpは毎ループ仕込み、鳴る/鳴らないはこのゲートで即時開閉(=モード切替にすぐ追従)
    const thumpBus=c.createGain(); thumpBus.gain.value=dancePartyOn?1:0; thumpBus.connect(bassBus);
    danceThumpBus=thumpBus;
    danceFirstBass=true;             // 頭のベース制御用(パーティ=最初の拍頭を出さず後拍から / ライト=最初の1音を弱める)
    danceT0=c.currentTime+0.1;        // 拍0の時刻(動き側 danceClock と共有)
    let nextT=danceT0;
    const tick=()=>{
      const t0=nextT;
      // パーティは後ノリ: キックは拍頭のまま、ベースとバックビート系をわずかに後ろへ溜める
      const laid=dancePartyOn?step*0.09:0;
      for(let i=0;i<STEPS;i++){ const t=t0+i*step, tL=t+laid;
        const b=D_BASS[i]; if(b){ const bf=fM(midiOf(b));
          const first=danceFirstBass; danceFirstBass=false;                                  // 再生開始後の最初のベース1音か
          const skip=first && dancePartyOn;                                                  // パーティは最初の拍頭ベースを出さず、後拍から始める(頭の違和感を防ぐ)
          const intro=(first && !dancePartyOn)?0.45:1;                                        // ライトは最初の1音だけ弱める
          if(!skip){
            const back=dancePartyOn && (i%4===2);                                            // 後拍=キックの裏に来るベース(2/6/10/14)
            blip(c,bassBus,bf,tL,step*1.6,(back?0.66:0.5)*intro,'triangle');                  // ベース(三角・専用バス経由/後ノリ/後拍を強調)
            dthump(c,danceThumpBus,bf,tL,step*1.7,(back?1.3:1)*intro);                        // 「ずん/どん」の太いサブベース(後拍を強調)
          }
        }
        // リード(矩形＋軽いビブラート)。ライト=メロディ主役で前へ / パーティ=ベースに譲って控えめ
        const l=D_LEAD[i]; if(l) blip(c,bus,fM(midiOf(l)),t,step*0.92,dancePartyOn?0.26:0.40,'square',0.008);
        if(i%4===0) dkick(c,bus,t);                                                          // 4つ打ちキック(拍頭=アンカー)
        if(i%2===1) sparkle(c,bus,tL,0.022,0.10);                                            // ハット(裏/後ノリ)
        if(i===4||i===12) sparkle(c,bus,tL,0.055,0.18);                                      // スネア風(後ノリ)
        if(dancePartyOn){                                                                    // パーティ: ビートを効かせる
          if(i%4===0) dkick(c,bus,t);                                                        //   キックを重ねて四つ打ちを太く(拍頭)
          if(i%4===2) sparkle(c,bus,tL,0.11,0.22);                                           //   オフビートのオープンハット(ツー/後ノリ)
          if(i===4||i===12) dclap(c,bus,tL);                                                 //   バックビートのクラップ(パンッ/後ノリ)
        }
      }
      nextT+=loopDur;
      danceTimer=setTimeout(tick, loopDur*1000-55);   // 1ループぶん先読みして繋ぐ
    };
    danceTimer=setTimeout(tick,0);   // ガード成立用に timer をセット → tick が自分で次を予約
  };
  // パーティモードのON/OFF: ベース専用バスを滑らかに増強/通常へ戻す(再生中のみ効く)
  const danceParty=on=>{
    dancePartyOn=!!on;
    if(!danceBassBus||!danceBassEQ) return;
    const c=ac(); if(!c) return; const n=c.currentTime, tc=0.08;
    danceBassBus.gain.setTargetAtTime(dancePartyOn?BASS_PARTY_GAIN:1, n, tc);
    danceBassEQ.gain.setTargetAtTime(dancePartyOn?BASS_PARTY_EQ:0, n, tc);
    if(danceThumpBus) danceThumpBus.gain.setTargetAtTime(dancePartyOn?1:0, n, 0.02); // ベースの入り/出を即時に
    if(danceBus) danceBus.gain.setTargetAtTime(dancePartyOn?DANCE_MASTER_PARTY:DANCE_MASTER, n, tc); // 総音量をモード間でそろえる(切替の段差を消す)
  };
  // 鳴っているグルーヴを fadeT 秒でフェードして片付ける(共通処理)。
  const fadeOut=fadeT=>{
    if(danceTimer){ clearTimeout(danceTimer); danceTimer=null; }
    danceT0=null; danceBassBus=null; danceBassEQ=null; danceThumpBus=null;
    const g=danceBus; danceBus=null; if(!g) return;
    try{ const c=ac(), n=c.currentTime;
      g.gain.cancelScheduledValues(n); g.gain.setValueAtTime(Math.max(g.gain.value,0.0001),n);
      g.gain.exponentialRampToValueAtTime(0.0001,n+fadeT);
    }catch(e){}
    setTimeout(()=>{ try{g.disconnect();}catch(e){} },fadeT*1000+230);
  };
  // 4小節後の自動終了: ゆっくりフェードし、ラッチを立てて「挿しっぱなしでも再開しない」状態にする。
  // (スピーカーのソケットは毎フレーム danceStart を呼ぶため、これが無いと即再開してフェードしない)
  const danceEnd=(fadeT=2.0)=>{ danceLatched=true; fadeOut(fadeT); };
  // スピーカー抜去: すっと止め、ラッチを解除(次に挿せばまた最初から踊れる)。
  const danceStop=()=>{ danceLatched=false; fadeOut(0.22); };

  global.playPico=playPico;
  global.trainPass=trainPass;   // 電車の通過音(プラレール演出から呼ぶ)
  global.danceStart=danceStart; // ダンスのグルーヴ開始(スピーカー挿入)
  global.danceStop=danceStop;   // ダンスのグルーヴ停止(スピーカー抜去)
  global.danceEnd=danceEnd;     // 4小節後の自動終了(ゆっくりフェード＋抜くまで再開しない)
  global.danceParty=danceParty; // パーティモード(ダーク＋ダンス)でベース増強
  // グルーヴの拍0からの経過秒。動き側がこれを読んで同じ時計で拍を刻む。
  // 音が実際に鳴っている(running)ときだけ返す。suspended(未解錠=ドラッグで挿しただけ等)では
  // currentTime が止まり 0 を返し続けて L-chika が1文字で固まるため、null を返して
  // 読み手(L-chika/ダンサー)を rAF フォールバック=テンポ刻みへ逃がす。
  global.danceClock=()=>{ if(danceT0==null) return null;
    const c=ac(); if(!c || c.state!=='running') return null;
    return Math.max(0, c.currentTime - danceT0); };
  global.audioCtx=ac;   // ページ共通の AudioContext を公開(全効果音で共有)

  // 初回のユーザー操作で AudioContext を解錠する(autoplay制限で suspended のままを防ぐ)
  // iOS Safari は touchstart/pointerdown を有効な操作と認めず、touchend/pointerup/click
  // などの「離散的な操作の完了」でしか resume できない。そのため down 系だけでなく up 系も拾い、
  // かつ実際に running になるまでリスナを外さない(1回の取りこぼしで解錠不能になるのを防ぐ)。
  const GEST=['pointerdown','pointerup','mousedown','touchstart','touchend','keydown','click'];
  const detach=()=> GEST.forEach(t=>global.removeEventListener(t,unlock,true));
  const unlock=()=>{ gestured=true;   // 操作を記録→生成＋resume(無音バッファは使わない=device error回避)
    let c=null; try{ c=ac(); }catch(e){}
    if(!c) return;
    if(c.state==='running'){ detach(); return; }
    try{ const p=c.resume(); const done=()=>{ if(c.state==='running') detach(); };   // resume は非同期: running を待ってから外す
      if(p&&p.then) p.then(done,()=>{}); else done(); }catch(e){}
  };
  GEST.forEach(t=>global.addEventListener(t,unlock,true));
})(window);
