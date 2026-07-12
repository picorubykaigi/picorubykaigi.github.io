const rnd=(a,b)=>a+Math.random()*(b-a);

// スピーカー演出のテンポ(BPM)。sound.js のグルーヴと縁ボードのバウンス/ウェーブ周期を揃える単一ソース。
const DANCE_BPM=144;

// split the logo into per-character LEDs (keeps color boundaries like .picoruby)
document.querySelectorAll('.title .prk').forEach(prk=>{
  let i=0;
  const chikaify=node=>{
    [...node.childNodes].forEach(child=>{
      if(child.nodeType===Node.TEXT_NODE){
        const frag=document.createDocumentFragment();
        [...child.textContent].forEach(ch=>{
          const s=document.createElement('span');
          s.className='l-chika'; s.textContent=ch; s.dataset.ch=ch; s.style.setProperty('--i',i++);
          frag.appendChild(s);
        });
        child.replaceWith(frag);
      }else if(child.nodeType===Node.ELEMENT_NODE){
        chikaify(child);
      }
    });
  };
  chikaify(prk);
});

// ---- ダンス中の L-chika: 音の拍に合わせて1文字ずつ点灯 ----
//   通常の CSS チェイス(frame-lit/l-chika)は読み込み時から自走し、音の拍とは位相が合わない
//   (CSS は音のクロックを読めない)。ダンス中だけ JS が danceClock(音と同期した経過秒・拍0起点)で
//   「2拍ごとに次の文字」を .beat-lit で点灯=拍に正確に合わせる。
(function(){
  const spans=[...document.querySelectorAll('.title .prk .l-chika')];
  if(!spans.length) return;
  const N=spans.length;
  const beat=60/DANCE_BPM;
  const STEP=beat*2;             // 2拍ごとに次の文字
  const LIT=0.29;                // 点灯保持(秒)
  const LEAD=0.06;               // 視覚スナップを音より少し先行(ダンサーの LEAD と揃える)
  // CSS チェイス(styles.css の frame-lit/l-chika)も同じ STEP・周期=N×STEP で回す。
  // ここを一致させることで、非ダンス時のチェイスとパーティの拍刻みが同じテンポになり、乗っ取りも段差なく繋がる。
  const STEP_MS=STEP*1000, CYC_MS=N*STEP_MS;
  // ダンス中(スピーカー挿入=dance-on)なら同期。チップ未挿入(fx-lchika-off)時は L-chika 自体が消灯。
  const isSync=()=>{ const b=document.body.classList;
    return b.contains('dance-on') && !b.contains('fx-lchika-off'); };
  // CSS チェイスの現在位置(最後に光った文字)を WAAPI の currentTime から推定。
  // 全文字は同じ開始時刻で回るので先頭の経過時間(ms)から: 周期(N×STEP)内の位相 / STEP。
  const cssLetter=()=>{
    try{ const a=spans[0].getAnimations(); if(!a.length||a[0].currentTime==null) return 0;
      const p=((a[0].currentTime%CYC_MS)+CYC_MS)%CYC_MS;
      const c=parseFloat(spans[0].style.getPropertyValue('--chase0'))||0;   // 前回の続き再開ぶんを足し戻す
      return ((Math.min(N-1, Math.floor(p/STEP_MS))+c)%N+N)%N;
    }catch(e){ return 0; }
  };
  let active=false, pending=false, base=0, litIdx=-1, cur=0, myT=0, lastTs=0;
  const clearLit=()=>{ if(litIdx>=0){ spans[litIdx].classList.remove('beat-lit'); litIdx=-1; } };
  // CSS チェイスが今「消灯の合間(直前の文字が光り終え、次がまだ)」かどうか。点灯途中に乗っ取ると
  // その文字のフラッシュを切って飛んで見えるので、合間になるまで待ってから引き継ぐ。
  const cssInGap=()=>{
    try{ const a=spans[0].getAnimations(); if(!a.length||a[0].currentTime==null) return true;
      const p=((a[0].currentTime%CYC_MS)+CYC_MS)%CYC_MS;
      return (p%STEP_MS)>340;                            // スロット内 点灯は ~20–323ms。それ以降=合間(周期=N×STEPで末尾の余白は無い)
    }catch(e){ return true; }
  };
  const doActivate=()=>{
    const dc=window.danceClock?window.danceClock():null;
    myT=(dc!=null)?dc:0; lastTs=0;                        // フォールバック時計の起点を音時計に合わせる
    const clk=myT+LEAD, step0=Math.floor(clk/STEP), within0=clk-step0*STEP;
    const firstLitStep=(within0<LIT)?step0:step0+1;      // 次に点灯するステップ(今が消灯位相なら次の拍)
    base=(cssLetter()+1)-firstLitStep;                   // その点灯が「直前に光った文字の次」になるよう逆算=飛ばさない
    spans.forEach(s=>s.classList.add('beat-driven'));    // CSS チェイスを止め JS に明け渡す
  };
  const onDeactivate=()=>{
    clearLit();
    // CSS チェイスを頭からでなく「最後の文字の次」から再開させる。--chase0 を入れてから animation を戻す。
    const next=(((cur+1)%N)+N)%N;
    spans.forEach(s=>s.style.setProperty('--chase0', String(next)));
    spans.forEach(s=>s.classList.remove('beat-driven')); // CSS チェイス再開(続きから)
  };
  const tick=ts=>{
    const on=isSync();
    if(on){
      if(!active && !pending) pending=true;              // 入場: まず CSS の合間を待つ(点灯中の文字を切らない)
      if(pending && cssInGap()){ pending=false; active=true; doActivate(); }
    } else {
      if(active) onDeactivate();
      active=false; pending=false;
    }
    if(active){
      // 拍時計: 音(danceClock)優先。4小節後の自動終了で音時計が null になっても(dance-on は残る)、
      // ダンサー同様 rAF 累積(myT)へフォールバックして拍テンポで動き続ける=固まらない。
      const dt=lastTs?Math.min(0.05,(ts-lastTs)/1000):0; lastTs=ts;
      const dc=window.danceClock?window.danceClock():null;
      if(dc!=null) myT=dc; else myT+=dt;
      const clk=myT+LEAD;
      const step=Math.floor(clk/STEP);
      const within=clk-step*STEP;
      const idx=(((base+step)%N)+N)%N;
      cur=idx;                                            // 終了時にこの「次」から CSS チェイスを継ぐ
      if(within<LIT){ if(idx!==litIdx){ clearLit(); spans[idx].classList.add('beat-lit'); litIdx=idx; } }
      else clearLit();
    }
    requestAnimationFrame(tick);
  };
  requestAnimationFrame(tick);
})();

// sparkles around the ruby
document.querySelectorAll('.scene').forEach(scene=>{
  for(let i=0;i<4;i++){
    const s=document.createElement('span'); s.className='sparkle';
    s.style.cssText=`left:${rnd(30,68)}%;top:${rnd(4,38)}%;--sd:${rnd(1.6,3).toFixed(2)}s;animation-delay:${(-rnd(0,3)).toFixed(2)}s`;
    scene.appendChild(s);
  }
});

// ruby: 丸い LED をひと粒ずつ「きらっ」と一瞬光らせる。
// 1粒ずつ順にあちこちを閃かせて渡り歩く。
(function(){
  const host=document.querySelector('.ruby-led'); if(!host) return;
  // 11列×9行の菱形グリッド上の点灯セル。[x,y] は host 幅/高に対する割合。
  const LEDS=[
    [.315,.052],[.408,.052],[.500,.052],[.592,.052],[.683,.052],
    [.224,.167],[.316,.167],[.408,.167],[.500,.167],[.592,.167],[.683,.167],[.776,.167],
    [.132,.281],[.224,.281],[.316,.281],[.408,.281],[.500,.281],[.592,.281],[.683,.281],[.775,.281],[.867,.281],
    [.040,.395],[.132,.395],[.224,.395],[.316,.395],[.408,.395],[.500,.395],[.592,.395],[.683,.395],[.775,.395],[.867,.395],[.959,.395],
    [.132,.507],[.224,.507],[.316,.507],[.408,.507],[.500,.507],[.592,.507],[.683,.507],[.775,.507],[.867,.507],
    [.224,.619],[.316,.619],[.408,.619],[.500,.619],[.592,.619],[.683,.619],[.775,.619],
    [.316,.730],[.408,.730],[.500,.730],[.592,.730],[.684,.730],
    [.408,.839],[.500,.839],[.592,.839],
    [.500,.950],
  ];
  const dots=LEDS.map(([x,y])=>{
    const d=document.createElement('span'); d.className='led-glint';
    d.style.left=(x*100).toFixed(2)+'%'; d.style.top=(y*100).toFixed(2)+'%';
    host.appendChild(d); return d;
  });
  // ひと粒を一瞬、斜めに光らせる。
  const kira=d=>{
    if(!d || d.classList.contains('kira')) return;
    d.classList.add('kira');
    d.addEventListener('animationend',()=>d.classList.remove('kira'),{once:true});
  };
  const pick=()=>dots[(Math.random()*dots.length)|0];
  // 環境演出: 完成/未完成にかかわらず、1粒ずつ順に渡り歩く。
  (function loop(){
    kira(pick());
    setTimeout(loop, 560+Math.random()*900);
  })();
  // 完成(body.ruby-full)時だけの上乗せ: 右上に固定したドット絵の十字(cross)を定期的に光らせる。
  const crossIdx=LEDS.reduce((b,p,i)=>Math.hypot(p[0]-0.70,p[1]-0.19)<Math.hypot(LEDS[b][0]-0.70,LEDS[b][1]-0.19)?i:b,0);
  const crossEl=document.createElement('span'); crossEl.className='cross';
  crossEl.dataset.x=LEDS[crossIdx][0]; crossEl.dataset.y=LEDS[crossIdx][1];
  crossEl.style.setProperty('--u','2px');                                  // ピクセル単位(偶数=ドット絵がボケない)
  crossEl.style.setProperty('--kd',(0.52+Math.random()*0.2).toFixed(2)+'s'); // 点滅1回の長さ
  crossEl.addEventListener('animationend',()=>crossEl.classList.remove('go'));
  host.appendChild(crossEl);
  const crossFlash=()=>{
    crossEl.style.setProperty('--ka',(0.86+Math.random()*0.1).toFixed(2));
    crossEl.style.left=Math.round(crossEl.dataset.x*host.clientWidth)+'px';   // 整数pxへスナップ(にじまない)
    crossEl.style.top =Math.round(crossEl.dataset.y*host.clientHeight)+'px';
    crossEl.classList.remove('go'); void crossEl.offsetWidth; crossEl.classList.add('go');
  };
  (function crossLoop(){
    if(document.body.classList.contains('ruby-full')) crossFlash();
    setTimeout(crossLoop, 2500+Math.random()*300);   // 定期的(約2.5〜2.8s)
  })();
  // モーター連動フック
  window.rubyGlint=function(){
    kira(pick());
    if(Math.random()<0.4) setTimeout(()=>kira(pick()), 90+Math.random()*120);
  };
})();

// モバイル(縦)判定。768px 以上=デスクトップ型(横一列ソケット)、以下=モバイル型(ソケットをRuby直下へ再構成)。
const BB_MOBILE=()=>window.matchMedia('(max-width: 767px)').matches;
// モバイル: 4部品(seg7/speaker/motor/chip)のソケットをRuby直下に横一列で並べる。バッテリーのソケットは
// 電源レール上に別置き(配置の詳細は下の battery ソケット)。部品本体の初期位置はソケットに連動せず
// ランダムに散らす(下の defaultPos)。
const M_DX={ seg7:-102, speaker:-6, motor:58, chip:128 };  // Ruby中心からの各ソケット中心オフセット(隙間20px)
const M_SOCKET_GAP=24;   // ソケット行: Ruby下端から1レール(穴ピッチ)あけて配置
const M_BAT_RIGHT=50;    // バッテリーソケット(モバイル): ステージ右端から中心までの距離(右上レール)

// ===== 部品スナップ共有定義(ドラッグ／回路の両方で使用) =====
const BB_GRID=24;
// 背景レールの水平シフト量(px)。Ruby先端に穴列を合わせるため背景をずらした量を
// ここに一元化し、部品/ソケット/電光掲示板の脚など全スナップの x がこれに追従する。
let BB_BGX=0;
const BB_PIN={
  // chip=上下4ピンのみ穴基準(左右は飾り) / battery=±端子 / motor=2リード / speaker=四隅ネジ穴(正方形)
  chip:[[0.2925,0.003],[0.687,0.003],[0.687,0.979],[0.2925,0.979]],
  battery:[[0.4805,0.005],[0.4805,0.984]],
  motor:[[0.206,0.9785],[0.769,0.9785]],
  speaker:[[0.17,0.17],[0.83,0.17],[0.83,0.83],[0.17,0.83]],
  seg7:[[0.12,0.95],[0.88,0.95]],                  // 下辺の左右2点(ピンヘッダ想定)
};
const BB_SNAPOFF={ chip:[0,12], motor:[0,12], speaker:[0,12], seg7:[0,12] };   // 12=穴上(12+24n) / 0=穴間(24n) / [x,y]=軸別
const BB_NUDGE={ motor:[1,2] };                    // スナップ後の見た目微調整[x,y]px
const bbSnapP=(v,part,ax)=>{ const o=BB_SNAPOFF[part];
  // x軸(ax=0)は背景シフト量 BB_BGX ぶん原点をずらして、見た目の穴列に合わせる
  const off=(Array.isArray(o)?o[ax]:(o!=null?o:12)) + (ax===0?BB_BGX:0);
  return Math.round((v-off)/BB_GRID)*BB_GRID+off; };
const bbAnchor=part=>{ const p=BB_PIN[part]; if(!p) return [0.5,0.5];
  let ax=0,ay=0; p.forEach(q=>{ax+=q[0];ay+=q[1];}); return [ax/p.length, ay/p.length]; };
// (left,top: ステージ基準px)→ 接点を穴に合わせたスナップ位置[x,y]
function bbSnapPos(part, left, top, W, H, stageH){
  const a=bbAnchor(part);
  // モバイルの横一列4部品(seg7/speaker/motor/chip)は y を上端スナップで揃える。
  // ピン位置基準(部品ごとに異なる)だと部品高の差でソケット上端が段差になるため、各部品の上端を
  // 同じ穴行へ合わせて4ソケットを同じy位置(上辺)に整列させる(ドロップ時も同じ行に吸着=判定一致)。
  const ay=(BB_MOBILE() && part!=='battery') ? 0 : a[1];
  const px=left+a[0]*W, py=top+ay*H;
  const x=bbSnapP(px,part,0)-a[0]*W;
  let y;
  if(part==='battery'){
    const cyEl=top+H/2, railY=(cyEl<96)?45:(cyEl>stageH-96)?(stageH-46):null; // 上/下レール帯なら中央へ
    y=(railY!=null)?(railY-H/2):(bbSnapP(py,part,1)-a[1]*H);
  } else { y=bbSnapP(py,part,1)-ay*H; }
  // 微調整(motor)はデスクトップの見た目用。モバイルは整列を崩さないよう無効化。
  const nd=BB_MOBILE()?[0,0]:(BB_NUDGE[part]||[0,0]);
  return [x+nd[0], y+nd[1]];
}

// ===== Ruby整列 + 背景シフト(BB_BGX)の一元処理 =====
// 縦: Rubyを最寄りの穴行へ寄せる。横: Ruby先端(=画像の水平中央)のXに穴列が来るよう
// 背景を水平シフトし、その量を BB_BGX に保存(部品/ソケット/脚の x スナップが追従)。
function bbApplyGridShift(){
  const stage=document.querySelector('.stage');
  const ruby=document.querySelector('.ruby-led');
  if(!stage||!ruby) return;
  const HOLE0=12.5, PITCH=24;
  const snap=v=>HOLE0+PITCH*Math.round((v-HOLE0)/PITCH);
  // Rubyの下方向オフセット(CSS .ruby-led と一致させる)。モバイル＆縦持ちタブレットは箱中央付近に置いて
  // Ruby上の余白を詰める(大きいオフセットだと scene箱の中でRubyが下寄りになり Ruby上が広がりすぎる)。
  const portraitTablet = window.matchMedia('(min-width: 768px) and (orientation: portrait)').matches;
  const ROFF = portraitTablet ? 'clamp(16px, 3svh, 36px)'      // 縦持ちタブレット: Ruby上を少し広く(下=Ruby↔KEYNOTEは詰まる)
             : BB_MOBILE()    ? 'clamp(5px, 1.2svh, 16px)'
             :                  'clamp(13px, 2.5vh, 28px)';
  const BASE='translate(-50%, calc(-50% + '+ROFF+'))'; // CSS と同じ中央配置
  ruby.style.transform=BASE;                          // まず素の中央配置に戻して測る
  const sr=stage.getBoundingClientRect();
  const r=ruby.getBoundingClientRect();
  const top=r.top-sr.top;
  const RAISE=3; // 穴行スナップ後、ほんのわずかだけ上げる(px)
  ruby.style.transform=BASE+' translate(0px, '+(snap(top)-top-RAISE).toFixed(2)+'px)'; // 縦だけ穴行へ＋微上げ
  const tipX=(r.left+r.right)/2-sr.left;              // 先端(水平中央)のX
  BB_BGX=tipX-snap(tipX);                             // 最寄り穴までのズレ=背景シフト量
  stage.style.backgroundPositionX=BB_BGX.toFixed(2)+'px';
}

// ---- 部品をドラッグ→穴にスナップ→配置をCookie保存 ----
(function(){
  const stage=document.querySelector('.stage'); if(!stage) return;
  bbApplyGridShift();   // 部品を並べる前に背景シフト量(BB_BGX)を確定させる
  const scatterPlaced=[];   // 初期スキャッターで確定した各部品の占有矩形(部品どうしの重なりを避ける)
  const setC=(k,v)=>{document.cookie=k+'='+v+';path=/;max-age=31536000';};
  const getC=k=>{const m=document.cookie.match('(?:^|; )'+k+'=([^;]*)');return m?m[1]:null;};
  const delC=k=>{document.cookie=k+'=;path=/;max-age=0';};
  // ドラッグの効果音(WebAudio)。actxはユーザー操作時に生成
  let actx;
  const ctx=()=>{ if(window.audioCtx) return window.audioCtx();   // ページ共通コンテキストを優先
    const AC=window.AudioContext||window.webkitAudioContext; if(!AC) return null;
    actx=actx||new AC(); if(actx.state==='suspended') actx.resume(); return actx; };
  // 持ち上げ「ひゅい」: ピッチが上がるスウィープ
  const pickUp=()=>{ try{ const c=ctx(); if(!c) return; const t=c.currentTime;
    const o=c.createOscillator(), g=c.createGain(); o.type='triangle';
    o.frequency.setValueAtTime(600,t); o.frequency.exponentialRampToValueAtTime(1750,t+0.12);
    g.gain.setValueAtTime(0.0001,t); g.gain.exponentialRampToValueAtTime(0.24,t+0.02);
    g.gain.exponentialRampToValueAtTime(0.0001,t+0.16);
    o.connect(g); g.connect(c.destination); o.start(t); o.stop(t+0.18);
  }catch(e){} };
  // 設置「ぱちっ」: ノイズの立ち上がり＋下降サインのポップ
  const dropPop=()=>{ try{ const c=ctx(); if(!c) return; const t=c.currentTime;
    const o=c.createOscillator(), g=c.createGain(); o.type='sine';
    o.frequency.setValueAtTime(960,t); o.frequency.exponentialRampToValueAtTime(300,t+0.07);
    g.gain.setValueAtTime(0.0001,t); g.gain.exponentialRampToValueAtTime(0.26,t+0.008);
    g.gain.exponentialRampToValueAtTime(0.0001,t+0.12);
    o.connect(g); g.connect(c.destination); o.start(t); o.stop(t+0.13);
    const n=Math.floor(c.sampleRate*0.012), buf=c.createBuffer(1,n,c.sampleRate), d=buf.getChannelData(0);
    for(let i=0;i<n;i++){ const e=1-i/n; d[i]=(Math.random()*2-1)*e*e; }
    const s=c.createBufferSource(); s.buffer=buf; const ng=c.createGain(); ng.gain.value=0.14;
    s.connect(ng); ng.connect(c.destination); s.start(t);
  }catch(e){} };
  // 跳ね返し「ぽよんっ」: やわらかいゴムボールが弾む弾力音(保護パーツに弾かれた時)。
  // 低い芯→高い頂点へ駆け上がる。高い頂点は減衰中に通し＋ローパスで丸め、余韻に減衰ビブラートを重ねて弾みを出す。
  const boing=()=>{ try{ const c=ctx(); if(!c) return; const t=c.currentTime;
    const base=300, top=1200, amp=0.2, dur=0.24, up=dur*0.58, dip=dur*0.34;
    const lp=c.createBiquadFilter(); lp.type='lowpass'; lp.Q.value=0.4;
    lp.frequency.setValueAtTime(1800,t); lp.frequency.exponentialRampToValueAtTime(820,t+dur*0.9); // 高域を丸めてゴムのやわらかさに
    lp.connect(c.destination);
    // 本体(丸いsine): 低い芯(ぽ)→ためて沈む→高い頂点へ駆け上がる(よ)。頂点では小さく=芯が主役
    const o=c.createOscillator(), g=c.createGain(); o.type='sine';
    o.frequency.setValueAtTime(base,t);
    o.frequency.setValueAtTime(base,t+dur*0.2);
    o.frequency.exponentialRampToValueAtTime(base*0.82,t+dip);
    o.frequency.exponentialRampToValueAtTime(top,t+up);
    o.frequency.exponentialRampToValueAtTime(top*1.03,t+up+0.03);
    g.gain.setValueAtTime(0.0001,t); g.gain.linearRampToValueAtTime(amp,t+0.04);
    g.gain.exponentialRampToValueAtTime(amp*0.22,t+up);
    g.gain.exponentialRampToValueAtTime(0.0001,t+dur);
    o.connect(g); g.connect(lp); o.start(t); o.stop(t+dur+0.04);
    // 余韻: 頂点音程を減衰ビブラートさせる
    const osc=c.createOscillator(), wg=c.createGain(); osc.type='sine'; osc.frequency.setValueAtTime(top,t+up);
    const lfo=c.createOscillator(), lg=c.createGain(); lfo.type='sine'; lfo.frequency.value=16;
    lg.gain.setValueAtTime(top*0.05,t+up); lg.gain.exponentialRampToValueAtTime(1,t+dur*1.4);
    lfo.connect(lg); lg.connect(osc.frequency);
    wg.gain.setValueAtTime(0.0001,t+up); wg.gain.linearRampToValueAtTime(amp*0.28,t+up+0.02);
    wg.gain.exponentialRampToValueAtTime(0.0001,t+dur*1.5);
    osc.connect(wg); wg.connect(lp); osc.start(t+up); osc.stop(t+dur*1.6); lfo.start(t+up); lfo.stop(t+dur*1.6);
  }catch(e){} };
  // 現在位置(left,top)から接点を穴に合わせたスナップ位置[x,y](共有の bbSnapPos を使用)
  const computeSnap=(el,left,top)=>bbSnapPos(el.dataset.part, left, top, el.offsetWidth, el.offsetHeight, stage.getBoundingClientRect().height);
  document.querySelectorAll('[data-part]').forEach(el=>{
    const id=el.dataset.part; if(!id) return;
    let sx,sy,ox,oy,moved=false,dragging=false,seed=null;
    // 初期配置: ステージ上のランダムな点(seed=1回だけ確定)を起点に、avoidProtected で保護要素を避けた
    // 最寄りの空きへ寄せる(基板にパーツがばらまかれた風)。
    const defaultPos=sr=>{
      if(!seed){
        const w=el.offsetWidth, h=el.offsetHeight;
        const minX=10, maxX=Math.max(10, sr.width-w-10);
        const minY=40, maxY=Math.max(40, sr.height-h-30);   // 上=電源レール下/下=余白を少し空ける
        seed={x:rnd(minX,maxX), y:rnd(minY,maxY)};
      }
      return avoidProtected(...computeSnap(el, seed.x, seed.y), false, true);   // 初期=strict(要素全体を避ける)
    };
    const rectOf=(e,sr,pad)=>{ const r=e.getBoundingClientRect(); if(r.width<1||r.height<1) return null;
      return {l:r.left-sr.left, t:r.top-sr.top, r:r.right-sr.left, b:r.bottom-sr.top, pad}; };
    // 「かぶってはいけないもの」= 中央UI各要素 + 他の各部品(ソケットは除外=挿入できる)。
    // 各行の [上,右,下,左] は保護矩形の縮め量px(正=内側へ詰める→その辺の外＝余白側に部品を置ける / 負=外へ広げる)。
    // display:none の要素(会場名/電光掲示板=ビューポート依存)は0サイズで自動スキップ。
    const PROTECT=[
      ['.title .picoruby', -2, 8, -2, 8],   // PicoRuby行: 横を詰めて脇に部品を置ける
      ['.title .kaigi',    -2, 20, -2, 20],   // Kaigi行: 横をさらに詰める
      ['.title .year',     -2, -2, -2, -2],
      ['.title .assemble', -2, -2, -2, -2],
      ['.ruby-led',  -3, -3, -3, -3],
      ['.venue-when', -2, -2, -2, -2],
      ['.venue-where',-2, -2, -2, -2],
      ['.keynotes',  -2, -2, -2, -2],
      ['.button',    -3,  4, 26, 4],   // 下を緩和(ラベル下の無地ボード〜下は置ける)
      ['.ticker',    12, -2, -2, -2],  // 上を詰めて基盤との間のかぶりは許容
    ];
    // strict(初期ロード)=インセット無視で各要素の全体(+2px)を避ける / 非strict(ドロップ)=インセット適用(端のかぶり許容)。
    const forbiddenRects=(sr, strict)=>{
      const out=[];
      for(const [s,it,ir,ib,il] of PROTECT){ const e=document.querySelector(s); const r=e&&e.getBoundingClientRect();
        if(!r || r.width<1 || r.height<1) continue;
        const T=strict?-2:it, R=strict?-2:ir, B=strict?-2:ib, L=strict?-2:il;
        out.push({l:r.left-sr.left+L, t:r.top-sr.top+T, r:r.right-sr.left-R, b:r.bottom-sr.top-B, pad:0});
      }
      document.querySelectorAll('[data-part]').forEach(p=>{ if(p===el) return; const b=rectOf(p,sr,2); if(b) out.push(b); });
      return out;   // ※ソケットは保護対象に含めない(=ドラッグでソケットに挿入できる)
    };
    // 自分のソケットに重ねている時は「挿入」とみなして回避しない(ソケットはRuby脇=保護Rubyに重なるため、
    // これが無いとRuby近接ソケットへ挿せない)。
    const ownSocketHit=(l,t)=>{ const s=document.querySelector('.circuit-slot--'+id); if(!s) return false;
      const sr=stage.getBoundingClientRect(), r=s.getBoundingClientRect();
      const sl=r.left-sr.left, st=r.top-sr.top, sR=r.right-sr.left, sB=r.bottom-sr.top;
      return l<sR && l+el.offsetWidth>sl && t<sB && t+el.offsetHeight>st; };   // 部品が自ソケットに重なる
    // 自ソケットに「ぴったり挿さっている」か(中心が±8px=通電ループの装着判定と同条件)。
    // ここで挿さっていない部品は位置を Cookie に記憶しない＝リロードで定位置(スキャッター)へ戻す。
    const seatedInSocket=(l,t)=>{ const s=document.querySelector('.circuit-slot--'+id); if(!s) return false;
      const sr=stage.getBoundingClientRect(), r=s.getBoundingClientRect();
      const scx=r.left-sr.left+r.width/2, scy=r.top-sr.top+r.height/2;
      const pcx=l+el.offsetWidth/2, pcy=t+el.offsetHeight/2;
      return Math.abs(pcx-scx)<=8 && Math.abs(pcy-scy)<=8; };
    const avoidProtected=(l,t,allowSocket,strict)=>{
      if(allowSocket && ownSocketHit(l,t)) return [l,t];   // 挿入(ドロップ)時だけソケットを許可。初期配置では Ruby を避ける
      const sr=stage.getBoundingClientRect();
      const w=el.offsetWidth, h=el.offsetHeight;
      const rects=forbiddenRects(sr, strict);
      const free=(x,y)=> !rects.some(z=>{ const p=z.pad||0; return x<z.r+p && x+w>z.l-p && y<z.b+p && y+h>z.t-p; });
      // 縦横とも多少のはみ出し可だが、掴めるぶん(GRAB)は必ず画面内に残す(小さい部品は全部・大きいものは一部のみはみ出す)。
      const GRAB=Math.min(w, 40), GRABY=Math.min(h, 40);
      const clampX=x=> Math.max(GRAB-w, Math.min(x, sr.width-GRAB));
      const clampY=y=> Math.max(8, Math.min(y, sr.height-GRABY));   // 上は据え置き(レール)/下は GRABY 残して はみ出し可
      const inX=x=> x>=GRAB-w && x<=sr.width-GRAB;
      const inY=y=> y>=8 && y<=sr.height-GRABY;
      if(free(l,t) && inY(t) && inX(l)) return [l,t];             // 既に空いていて掴める範囲ならそのまま
      for(let rad=1; rad<=30; rad++) for(let dx=-rad; dx<=rad; dx++) for(let dy=-rad; dy<=rad; dy++){
        if(Math.max(Math.abs(dx),Math.abs(dy))!==rad) continue;   // その半径の外周セルだけ
        const nx=l+dx*BB_GRID, ny=t+dy*BB_GRID;
        if(inY(ny) && inX(nx) && free(nx,ny)) return [nx,ny];
      }
      return [clampX(l), clampY(t)];
    };
    // 保存位置が「掴めるぶん(GRAB/GRABY)を画面内に残しているか」。多少のはみ出しは尊重(定位置へ戻さない)。
    const fits=(l,t,sr)=>{ const w=el.offsetWidth, h=el.offsetHeight, gx=Math.min(w,40), gy=Math.min(h,40);
      return l>=gx-w-2 && l<=sr.width-gx+2 && t>=6 && t<=sr.height-gy+2; };
    // 配置の確定/更新: 保存位置が現在ビューポートで画面内ならそれを尊重、画面外/未保存なら定位置へ。
    // (別幅で保存した Cookie やリサイズでも部品が画面外に取り残されない。ドラッグ中は触らない。)
    const reflow=()=>{
      if(dragging) return;
      const sr=stage.getBoundingClientRect();
      const saved=getC('pos_'+id);
      let l, t;
      if(saved){ const p=saved.split(',').map(Number);
        if(fits(p[0],p[1],sr)){ l=p[0]; t=p[1]; } else { [l,t]=defaultPos(sr); } }
      else { [l,t]=defaultPos(sr); }
      el.style.left=l+'px'; el.style.top=t+'px'; el.style.right='auto'; el.style.bottom='auto';
    };
    reflow();
    // ソケットは後続のIIFEで生成されるため、生成後(次フレーム)にもう一度評価してソケットも避ける。
    requestAnimationFrame(reflow);
    // ロゴはWebフォント(Bitcount)で幅が変わる/リサイズで基準位置が動く→確定後・リサイズで再評価。
    if(document.fonts && document.fonts.ready) document.fonts.ready.then(()=>requestAnimationFrame(reflow));
    let rt; window.addEventListener('resize',()=>{ clearTimeout(rt); rt=setTimeout(reflow,200); });
    el.addEventListener('pointerdown',e=>{
      if(e.button!==undefined && e.button!==0) return;
      const r=el.getBoundingClientRect(), sr=stage.getBoundingClientRect();
      ox=r.left-sr.left; oy=r.top-sr.top; sx=e.clientX; sy=e.clientY;
      dragging=true; moved=false;
      try{el.setPointerCapture(e.pointerId);}catch(_){}
    });
    el.addEventListener('pointermove',e=>{
      if(!dragging) return;
      const dx=e.clientX-sx, dy=e.clientY-sy;
      if(!moved && Math.hypot(dx,dy)<4) return;   // 4px未満はクリック扱い
      if(!moved) pickUp();                          // 持ち上げた瞬間「ひゅい」
      moved=true; el.classList.add('dragging');
      el.style.left=(ox+dx)+'px'; el.style.top=(oy+dy)+'px';
      el.style.right='auto'; el.style.bottom='auto';
    });
    const end=()=>{
      if(!dragging) return; dragging=false; el.classList.remove('dragging');
      if(moved){
        const [fx,fy]=computeSnap(el, parseFloat(el.style.left), parseFloat(el.style.top));
        const [ax,ay]=avoidProtected(fx,fy,true,false);   // ドロップ時=自ソケット挿入を許可＋インセット適用(端への多少のかぶり許容)
        const ejected = Math.round(ax)!==Math.round(fx) || Math.round(ay)!==Math.round(fy);
        if(ejected){
          // 保護スペースに被せて離した → 周辺へスライド+軽い回転(落下はしない)で弾き返す
          const rot=(Math.random()<0.5?-1:1)*(6+(Math.random()*6|0));   // 振れ角は控えめ(±6〜11°)
          el.style.setProperty('--eject-rot', rot+'deg');
          el.style.transition='left .42s cubic-bezier(.2,.75,.25,1), top .42s cubic-bezier(.2,.75,.25,1)';
          el.classList.add('ejecting');
          boing(); // 弾かれた「ぽよんっ」
          requestAnimationFrame(()=>{ el.style.left=ax+'px'; el.style.top=ay+'px'; });
          el.addEventListener('animationend', ()=>{ el.style.transition=''; el.classList.remove('ejecting'); }, {once:true});
        }else{
          el.style.left=fx+'px'; el.style.top=fy+'px';
          dropPop(); // 穴に「ぱちっ」
        }
        if(seatedInSocket(ax,ay)) setC('pos_'+id, ax+','+ay);   // 挿さった部品だけ位置を記憶
        else delC('pos_'+id);                                   // 未装着は記憶しない(リロードで定位置へ)
      }

    };
    el.addEventListener('pointerup',end);
    el.addEventListener('pointercancel',end);
    // ドラッグ直後のクリック(トグル/アクション発火)を抑制
    el.addEventListener('click',e=>{ if(moved){ e.preventDefault(); e.stopPropagation(); moved=false; } },true);
  });
})();

// ---- スピーカーに「音が鳴る」ヒントの吹き出しを出す ----
// ソケット未装着のときだけ表示。持ち上げ(.dragging)/装着(.lit-src)したら撤去して再表示しない。
(function(){
  const spk=document.querySelector('.bb-speaker'); if(!spk) return;
  const tip=document.createElement('span');
  tip.className='spk-hint'; tip.setAttribute('aria-hidden','true');
  tip.style.opacity='0';                         // 装着判定が出るまで隠す(装着済みなら出さない)
  // ドット絵の8分音符
  tip.innerHTML='<svg class="spk-ico" viewBox="0 0 7 7">'
    +'<path d="M3 0h1v6h-1z M4 0h3v1h-3z M6 1h1v2h-1z M0 5h3v2h-3z M1 4h2v1h-2z"/></svg>';
  spk.appendChild(tip);
  const done=()=>{                               // 持ち上げ/装着で撤去
    obs.disconnect();
    tip.addEventListener('transitionend',()=>tip.remove(),{once:true});
    tip.style.opacity='0';
    setTimeout(()=>tip.remove(),150);            // transitionend が来ない時の保険
  };
  const obs=new MutationObserver(()=>{
    if(spk.classList.contains('dragging')||spk.classList.contains('lit-src')) done();
  });
  obs.observe(spk,{attributes:true,attributeFilter:['class']});
  // 通電ループが装着状態(.lit-src)を確定するのを待ち、未装着なら表示する。
  requestAnimationFrame(()=>requestAnimationFrame(()=>{
    if(!spk.classList.contains('lit-src')) tip.style.opacity='';
  }));
})();

// ---- 配置で通電: 部品をソケットに挿す → その回路の演出がON(抜くとOFF) ----
(function(){
  const stage=document.querySelector('.stage'); if(!stage) return;
  const parts=document.querySelectorAll('[data-part]'); // 挿す部品(バッテリー/チップ)
  const logo=document.querySelector('.title .prk');
  const scene=document.querySelector('.scene');
  const rubyLed=document.querySelector('.ruby-led');
  const ticketBtn=document.querySelector('.button-icon.ticket');
  const proposalBtn=document.querySelector('.button-icon.proposal');
  if(!parts.length) return;
  const SW=54, SH=54;
  // 通電音: 他の効果音と同じくオシレーター1個の素朴なポップ。D6→G6 の2音グライドで、
  // 到達音を少しオーバーシュートさせて弾ませる。高域をひかえめに持ち上げて空気感(ヌケ)を足す。
  const connectSnd=()=>{ try{ const c=window.audioCtx&&window.audioCtx(); if(!c) return;
    const t=c.currentTime;
    const o=c.createOscillator(),g=c.createGain(); o.type='triangle'; // 輪郭は他の音と揃え、丸さはローパスで作る
    // 弾むグライド(前)とコインの跳んでホールドの中間: 素早く上に跳ねて軽くオーバーシュート→
    // 高い音を少しだけホールドしてから切れる。コインの歯切れを残しつつ寄りすぎない。
    o.frequency.setValueAtTime(1480,t);        // ぴ(F#6)を短く
    o.frequency.setValueAtTime(1480,t+0.04);
    o.frequency.exponentialRampToValueAtTime(2093,t+0.09);  // すっと上へ跳ねる(C7まで)
    o.frequency.exponentialRampToValueAtTime(1976,t+0.15);  // B6に着地してホールド
    g.gain.setValueAtTime(0.0001,t); g.gain.exponentialRampToValueAtTime(0.2,t+0.04); // 立ち上がりをゆるめて角を取る
    g.gain.exponentialRampToValueAtTime(0.09,t+0.15);  // すっと力が抜けて
    g.gain.exponentialRampToValueAtTime(0.0001,t+0.52); // 高音がきれいに鳴り残る(コインの気持ちよさ。音量は上げない)
    // triangleの輪郭(くっきり感)は残しつつ、上の角だけローパスで丸めて間の抜けたかわいさを出す
    const lp=c.createBiquadFilter(); lp.type='lowpass'; lp.frequency.value=2800; lp.Q.value=1;
    o.connect(g); g.connect(lp); lp.connect(c.destination); o.start(t); o.stop(t+0.54);
  }catch(e){} };
  // 不正解音: G5→D5 の2音(各わずかに下降)を、ビットクラッシュ(4bit)で8bitらしくざらつかせる。
  // 荒さは postlp(角取り)と原音ミックス(wet/dry)で抑え、他の効果音と馴染むマイルドな歪みにしてある。
  const wrongSnd=()=>{ try{ const c=window.audioCtx&&window.audioCtx(); if(!c) return;
    const t=c.currentTime;
    // 信号経路: 音 → lp(丸め) → [ws(歪み)→postlp(角取り)→wet] と [dry(原音)] を混ぜて出力
    const ws=c.createWaveShaper(); ws.oversample='4x';
    const curve=new Float32Array(1024), L=16; // 4bit=16段でビットクラッシュ
    for(let i=0;i<1024;i++){ const x=i*2/1024-1; curve[i]=Math.round(x*L)/L; }
    ws.curve=curve;
    const postlp=c.createBiquadFilter(); postlp.type='lowpass'; postlp.frequency.value=2400; postlp.Q.value=0.7; // 高域の荒さを角取り
    const wet=c.createGain(), dry=c.createGain(); wet.gain.value=0.6; dry.gain.value=0.4; // 原音を混ぜて荒さを薄める
    const lp=c.createBiquadFilter(); lp.type='lowpass'; lp.frequency.value=2300; lp.Q.value=1;
    lp.connect(ws); ws.connect(postlp); postlp.connect(wet); wet.connect(c.destination);
    lp.connect(dry); dry.connect(c.destination);
    const blip=(start,freq,dur,peak,end)=>{
      const o=c.createOscillator(),g=c.createGain(); o.type='triangle';
      o.frequency.setValueAtTime(freq,start);
      o.frequency.exponentialRampToValueAtTime(end,start+dur); // freq→endへわずかに下降
      g.gain.setValueAtTime(0.0001,start); g.gain.exponentialRampToValueAtTime(peak,start+0.006);
      g.gain.exponentialRampToValueAtTime(0.0001,start+dur);
      o.connect(g); g.connect(lp); o.start(start); o.stop(start+dur+0.01);
    };
    blip(t,784,0.14,0.15,740);        // G5
    blip(t+0.16,587,0.22,0.15,523);   // D5(ワ〜ン↓)
  }catch(e){} };
  const body=document.body;
  // 各ソケット: 所定の部品(part)が所定の位置(place)に挿さる演出ON。いずれも scene を基準に置く。
  // デスクトップ: Ruby の縦中心(rubyCY)に各ソケット中心を合わせて横1列。左から seg7→speaker→(Ruby)→motor→chip。
  // モバイル(BB_MOBILE): Ruby 下端の下へ横一列に再配置(mPlace。上端を揃える)。
  const cx  =(a,sr)=>a.left-sr.left+a.width/2;     // Ruby の水平中心(scene中心)
  const rubyCY=(a,sr)=>{ if(rubyLed){ const r=rubyLed.getBoundingClientRect(); return r.top-sr.top+r.height/2; } return a.top-sr.top+a.height/2; };
  const rubyBottom=(a,sr)=>{ if(rubyLed){ const r=rubyLed.getBoundingClientRect(); return r.top-sr.top+r.height; } return a.top-sr.top+a.height; };
  const rowTop=(a,sr,h)=>rubyCY(a,sr)-h/2;         // 高さhの部品をRuby縦中心に合わせた上端Y
  // モバイルのソケット左上座標: Ruby下端から1レールあけ、4ソケットの「上端」を揃える。
  const mPlace=(a,sr,part,w,h)=>
    ({ sx:cx(a,sr)+M_DX[part]-w/2, sy:rubyBottom(a,sr)+M_SOCKET_GAP });
  // 「PicoRubyKaigi」が1行に収まっているか(<wbr>で PicoRuby/Kaigi が折り返すと2行になる)。
  const logoPico=document.querySelector('.title .picoruby');
  const logoKaigi=document.querySelector('.title .kaigi');
  const logoOneLine=()=> !!logoPico && !!logoKaigi &&
    Math.abs(logoPico.getBoundingClientRect().top - logoKaigi.getBoundingClientRect().top) < 4;
  // バッテリーソケットの水平中心: ロゴ1行目の末尾文字の真上。1行なら Kaigi の "i"、折り返し時は PicoRuby の "y"。
  const lastKaigiLed=document.querySelector('.title .kaigi .l-chika:last-child');
  const lastPicoLed =document.querySelector('.title .picoruby .l-chika:last-child');
  const batCenterX=sr=>{
    const el=logoOneLine()?lastKaigiLed:lastPicoLed;
    if(el){ const r=el.getBoundingClientRect(); return r.left-sr.left+r.width/2; }
    return sr.width-166.5;   // フォールバック: 従来の右端-180 + 幅27/2
  };
  const SOCKETS=[
    // 7セグ → スピーカーのさらに左 → 会期カウントダウンが点灯(抜くと消灯)。
    scene && { part:'seg7', anchor:scene, h:53,
               get w(){ const e=document.querySelector('.bb-seg7'); return e?e.offsetWidth:108; }, // 桁数で部品幅が変わる→追従
               place(a,sr){ const w=this.w; return BB_MOBILE() ? mPlace(a,sr,'seg7',w,53)
                            : ({ sx:cx(a,sr)-256-w/2, sy:rowTop(a,sr,53) }); },   // 中心(cx-256)固定。3桁=cx-310 / 2桁は中心保ったまま縮む
               apply:on=>{ const el=document.querySelector('.bb-seg7'); if(el) el.classList.toggle('lit', on); } },
    // スピーカー → Ruby の左 → 縁のマイコンボードが一斉に踊る(グルーヴ再生)。抜くと停止。
    scene && { part:'speaker', anchor:scene, w:44, h:44,
               place:(a,sr)=> BB_MOBILE() ? mPlace(a,sr,'speaker',44,44)
                                          : ({ sx:cx(a,sr)-164, sy:rowTop(a,sr,44) }),
               apply:on=>{ body.classList.toggle('dance-on', on);
                 if(window.prarailDancing) window.prarailDancing(on);   // 踊り中はプラレールのチラ見せを止める
                 // パーティモード=ダーク(バッテリー)＋ダンス(スピーカー)。先に状態を確定してから開始すると、
                 // パーティ状態でいきなり始めても danceStart が最初から正しいモードでフェードインでき、入りのノイズが出ない
                 if(window.danceParty) window.danceParty(on && body.classList.contains('dark'));
                 if(on){ if(window.danceStart) window.danceStart(DANCE_BPM); }
                 else  { if(window.danceStop)  window.danceStop(); } } },
    // モーター → Ruby の右 → 挿した瞬間にプラレールが右→左へ一度走り抜ける(通過音つき)。
    // 挿入前の待機/チラ見せ・発進・帰還はプラレールコントローラ(window.prarailMotor)が担う。
    scene && { part:'motor',   anchor:scene, w:44, h:57,
               place:(a,sr)=> BB_MOBILE() ? mPlace(a,sr,'motor',44,57)
                                          : ({ sx:cx(a,sr)+104, sy:rowTop(a,sr,57) }),
               apply:on=>{ if(window.prarailMotor) window.prarailMotor(on); } },
    // チップ → モーターの右(行の右端) → PicoRubyKaigi がLチカ。
    scene && { part:'chip',    anchor:scene, w:56, h:56,
               place:(a,sr)=> BB_MOBILE() ? mPlace(a,sr,'chip',56,56)
                                          : ({ sx:cx(a,sr)+204, sy:rowTop(a,sr,56) }),
               apply:on=>body.classList.toggle('fx-lchika-off', !on) },
    // バッテリー → 電源レール(赤+/青-)をまたぐ → ダークモード(暗闇でボードが光る)。
    // 電光掲示板が出るデスクトップ(≥768px): ロゴ1行目末尾文字(1行=Kaigiの"i"/折り返し=PicoRubyの"y")の真上
    // (部品のスナップ格子に丸める)。電光掲示板の無いモバイル(<768px): 右上レール。y は両方とも電源レール据え置き。
    {            part:'battery', anchor:stage, w:27, h:46,
               place(a,sr){ return BB_MOBILE() ? ({ sx:a.width-M_BAT_RIGHT-13.5, sy:24 })
                                               : ({ sx:bbSnapP(batCenterX(sr),'battery',0)-this.w/2, sy:24 }); },
               apply:on=>{ body.classList.toggle('dark', on);
                 // ダンス中にダーク切替されたらパーティモードのベース増強も追従
                 if(window.danceParty) window.danceParty(on && body.classList.contains('dance-on')); } },
  ].filter(Boolean);
  SOCKETS.forEach(s=>{ s.el=document.createElement('div'); s.el.className='circuit-slot circuit-slot--'+s.part; stage.appendChild(s.el); s.was=false; s.wasTouch=false; s.wasWrong=false; s.apply(false); });
  let endlessDance=false, speakerWasIn=false, speakerEverDragged=false;   // スピーカーを「最後の1個」としてはめて完成させたか
  const blogLink=document.querySelector('.blog-link');
  function frame(){
    const sr=stage.getBoundingClientRect();
    SOCKETS.forEach(s=>{
      const a=s.anchor.getBoundingClientRect();
      const p0=s.place(a,sr); const W=s.w, H=s.h;
      // ソケット枠を「部品が実際に収まる格子位置」に合わせる
      const [sx,sy]=bbSnapPos(s.part, p0.sx, p0.sy, W, H, sr.height);
      s.el.style.left=sx+'px'; s.el.style.top=sy+'px'; s.el.style.width=W+'px'; s.el.style.height=H+'px';
      // Keep the blog link right-aligned just left of the battery socket (its x moves with the logo width)
      if(s.part==='battery' && blogLink) blogLink.style.right=(sr.width-sx+18)+'px';
      const ccx=sx+W/2, ccy=sy+H/2; // ソケット中心
      let inSlot=false, hit=null, touching=false, wrong=false;
      parts.forEach(p=>{
        const r=p.getBoundingClientRect();
        const cx=r.left-sr.left+r.width/2, cy=r.top-sr.top+r.height/2;
        const dx=Math.abs(cx-ccx), dy=Math.abs(cy-ccy);
        if(p.dataset.part===s.part){                                     // そのソケット専用の部品(=正解)
          if(p.classList.contains('dragging')){ if(dx<=22 && dy<=22) touching=true; } // ドラッグ中にソケットへ触れた(早め)
          else if(dx<=8 && dy<=8){ inSlot=true; hit=p; }                              // 離して ぴったり→モード
        }else{                                                           // 別の部品(=不正解)
          if(p.classList.contains('dragging')){ if(dx<=22 && dy<=22) wrong=true; }     // 触れた瞬間にも鳴らす(正解と対)
          else if(dx<=20 && dy<=20){ wrong=true; }                                     // 置いたとき
        }
      });
      s.apply(inSlot);
      s.el.classList.toggle('filled', inSlot);  // 挿さったら光を消す
      s.el.classList.toggle('hint', !inSlot);
      parts.forEach(p=>{ if(p.dataset.part===s.part) p.classList.toggle('lit-src', inSlot && p===hit); });
      if(touching && !s.wasTouch) connectSnd();          // ソケットに触れた瞬間に通電音
      if(wrong && !s.wasWrong) wrongSnd();               // 違う部品を置いた瞬間に「ぶぶーっ」
      s.wasTouch=touching;
      s.wasWrong=wrong;
      s.was=inSlot;
    });
    // Ruby周りの4部品(seg7/speaker/motor/chip)が全部そろうと、Rubyが強く輝く。バッテリーは別格(電源レール)なので除外。
    const RUBY_PARTS=['seg7','speaker','motor','chip'];
    const full=SOCKETS.filter(s=>RUBY_PARTS.includes(s.part)).every(s=>s.was);
    body.classList.toggle('ruby-full', full);
    // スピーカーを「最後の1個」として手で挿して完成させたときだけ無限ダンス(フェードしない)。
    // 他部品で完成させた場合や、リロードで最初から揃っている復元状態は対象外(通常どおりフェード)。
    const spk=[...parts].find(p=>p.dataset.part==='speaker');
    if(spk && spk.classList.contains('dragging')) speakerEverDragged=true;   // リロード復元では dragging が付かない
    const spkIn=SOCKETS.some(s=>s.part==='speaker'&&s.was);
    const othersIn=SOCKETS.filter(s=>RUBY_PARTS.includes(s.part)&&s.part!=='speaker').every(s=>s.was);
    if(speakerEverDragged && spkIn && !speakerWasIn) endlessDance=othersIn;   // 挿入の瞬間(out→in)に残り3部品がそろっていれば
    if(!spkIn || !full) endlessDance=false;             // スピーカーを抜く/どれか抜けて崩れたら解除
    speakerWasIn=spkIn;
    body.classList.toggle('dance-endless', endlessDance);
    if(endlessDance && window.danceEndless) window.danceEndless();   // 無限中は自動終了ラッチを解除し続ける
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
})();

// ---- イントロ誘導: しばらく経ってもソケットに収まっていない部品があると、時々「ぶるぶるっ」と震えて誘う ----
(function(){
  const parts=[...document.querySelectorAll('[data-part]')];
  if(!parts.length) return;
  const START=3000;   // ページ表示から3秒経ってから誘導開始
  const seated=p=>p.classList.contains('lit-src');                                  // ソケットにぴったり挿さっている
  const busy=p=>p.classList.contains('dragging')||p.classList.contains('ejecting'); // 操作中/弾き演出中は触らない
  // 吹き出し(spk-hint)が出ている部品は震えさせない(回転で吹き出しが左右に振られて見えるため)。
  const hinted=p=>!!p.querySelector('.spk-hint');
  const shiver=p=>{
    if(busy(p)||p.classList.contains('shiver')) return;
    p.classList.add('shiver');
    p.addEventListener('animationend',()=>p.classList.remove('shiver'),{once:true});
  };
  // 外れているパーツだけを対象に、ランダム順で1巡ずつローテーション(同じパーツが続けて偏らない)。
  let queue=[];
  const tick=()=>{
    if(!queue.length){                                     // 1巡し終えたら、その時点で外れているパーツで作り直す
      queue=parts.filter(p=>!seated(p)&&!busy(p)&&!hinted(p));
      for(let i=queue.length-1;i>0;i--){ const j=(Math.random()*(i+1))|0; const t=queue[i]; queue[i]=queue[j]; queue[j]=t; } // シャッフル
    }
    const p=queue.shift();
    if(p && !seated(p) && !busy(p) && !hinted(p)) shiver(p); // キュー作成後に挿された/掴まれた/吹き出し中のパーツは飛ばす
    setTimeout(tick, 2400+Math.random()*2600);             // 次の誘導まで(約2.4〜5.0s間隔)
  };
  setTimeout(tick, START);
})();

// ---- 電光掲示板ティッカー ----
(function(){
  const ticker=document.querySelector('.ticker');
  const track=ticker&&ticker.querySelector('.ticker-track');
  const tmpl=track&&track.querySelector('.ticker-unit');
  if(!tmpl) return;
  const SPEED=31;
  const build=()=>{
    [...track.querySelectorAll('.ticker-unit')].slice(1).forEach(n=>n.remove());
    const unitW=tmpl.getBoundingClientRect().width;
    const viewW=ticker.getBoundingClientRect().width;
    if(!unitW || !viewW) return;
    const perFill=Math.ceil(viewW/unitW)+1; // 1フィル=画面幅を確実に超えるユニット数
    const frag=document.createDocumentFragment();
    for(let i=1;i<perFill*2;i++) frag.appendChild(tmpl.cloneNode(true)); // 2フィルぶん
    track.appendChild(frag);
    const shift=unitW*perFill;
    track.style.setProperty('--shift', shift+'px');
    track.style.setProperty('--dur', (shift/SPEED).toFixed(1)+'s');
  };
  build();
  if(document.fonts&&document.fonts.ready) document.fonts.ready.then(build); // フォント確定後に再計測
  let t; window.addEventListener('resize',()=>{ clearTimeout(t); t=setTimeout(build,200); });
})();

// ---- 電光掲示板の脚(4本): ブレッドボードの穴列にスナップして配置 ----
// 穴は背景グリッド(24px)で 左から x=12.5 + 24n。.ticker-legs は stage 左0基準なので原点が一致。
// 左ペア(12%/24%)・右ペア(76%/88%)を目標に、各々を最寄りの穴列へ吸着させる。
(function(){
  const stage=document.querySelector('.stage');
  const legs=document.querySelector('.ticker-legs'); if(!stage||!legs) return;
  const PINW=6, HOLE0=12.5, PITCH=24;  // 穴は x も y も 12.5 + 24n(背景グリッド)
  const pins=[];
  for(let i=0;i<4;i++){ const p=document.createElement('i'); p.className='pin'; legs.appendChild(p); pins.push(p); }
  const snap=v=>HOLE0 + PITCH*Math.round((v-HOLE0)/PITCH); // 最寄りの穴(中心)へ
  // X は背景シフト量 BB_BGX に追従(穴列は 12.5 + BB_BGX + 24n に見える)
  const snapX=v=>BB_BGX + HOLE0 + PITCH*Math.round((v-BB_BGX-HOLE0)/PITCH);
  const layout=()=>{
    const sr=stage.getBoundingClientRect();
    const lr=legs.getBoundingClientRect();
    const w=lr.width; if(!w) return;
    // X: 目標位置(左ペア/右ペア)を最寄りの穴列へ(背景シフトに追従)
    [0.12, 0.24, 0.76, 0.88].forEach((f,i)=>{ pins[i].style.left=(snapX(f*w)-PINW/2)+'px'; });
    // Y: 下端(=LED上辺)は固定のまま、先端を最寄りの穴の行に合わせて脚の高さを可変に
    const bottomY=lr.bottom-sr.top;            // 脚の下端の y(LED上辺。CSS bottom 固定で安定)
    let h=bottomY-snap(bottomY-14);            // 目標長≈14px に近い穴行までの高さ
    if(h<9) h+=PITCH;                          // 短すぎたら一段上の穴へ
    legs.style.height=h+'px';
  };
  layout();
  let t; window.addEventListener('resize',()=>{ clearTimeout(t); t=setTimeout(layout,200); });
})();

// ---- Ruby先端のXに背景の穴列を合わせる(共有の bbApplyGridShift を使用) ----
// 実処理は bbApplyGridShift() に集約(BB_BGX を更新し、部品/ソケット/脚の x が追従)。
// ここでは初回・フォント確定後・リサイズで再適用するだけ。
(function(){
  bbApplyGridShift();
  if(document.fonts&&document.fonts.ready) document.fonts.ready.then(bbApplyGridShift);
  let t; window.addEventListener('resize',()=>{ clearTimeout(t); t=setTimeout(bbApplyGridShift,200); });
})();

// ---- プラレール: motor未挿入のあいだは右画面外で待機し、たまにヘッドだけチラ見せ。
//      motorを動力に挿した瞬間、一拍ガコンの溜め→右→左へ一度だけ走り抜ける(通過音つき)。
//      走り終えたら右外へ帰還。motorを抜くと、また「チラ見せ」に戻る。 ----
(function(){
  const stage=document.querySelector('.stage'); if(!stage) return;
  const train=document.querySelector('.prarail'); if(!train) return;
  const W=()=>train.offsetWidth;
  const stageW=()=>stage.getBoundingClientRect().width;
  const offRight=()=>stageW()+12;     // 右画面外(完全に隠れる)
  const offLeft =()=>-(W()+12);       // 左画面外
  const peekX   =()=>stageW()-46;     // ヘッドだけ 46px 顔を出す
  const setX=(x,dur,ease)=>{          // top:62% を保つため translateY(-50%) は固定
    train.style.transition = dur ? `transform ${dur}ms ${ease||'linear'}` : 'none';
    train.style.transform  = `translate(${x}px, -50%)`;
  };
  const wait=ms=>new Promise(r=>setTimeout(r,ms));
  setX(offRight(), 0);                // 初期=右外

  let token=0;        // 進行中シーケンスの世代(状態が変わると無効化して打ち切る)
  let inserted=false; // motor が挿さっているか
  let dancing=false;  // スピーカー演出(ダンス)中はチラ見せを止める

  // チラ見せ: motor が挿さるまで、不定間隔でヘッドを出し入れ(ダンス中は止める)
  async function idleLoop(my){
    while(my===token && !inserted && !dancing){
      await wait(2600+Math.random()*3200);          // 次の顔出しまで(2.6〜5.8s)
      if(my!==token || inserted) break;
      setX(peekX(), 520, 'ease-out'); await wait(560);  // ニュッ
      if(my!==token || inserted) break;
      await wait(420+Math.random()*520);                // ちょい保持
      if(my!==token || inserted) break;
      setX(offRight(), 420, 'ease-in'); await wait(440); // 引っ込む
    }
  }

  const motor=document.querySelector('.bb-motor'); // 走行中だけブルブルさせる対象
  // 単発走行: 溜め無しで即発進 → 右→左へ等速で走り抜ける(通過音) → 右外へ帰還
  async function runOnce(my){
    if(motor) motor.classList.add('driving');               // 走り出すと同時にモーターが回り始める
    try{
      setX(offRight(), 0); await wait(30);                   // 右外スタート位置を確定(これが無いと左へワープ)
      if(my!==token) return;
      const TRAVEL=1400;                                     // 走行(速め・[仮]の速さ感を踏襲)
      if(window.trainPass) window.trainPass(3.2, 0.32, 0.13);// 通過音(余韻長め・立ち上がり速め)
      setX(offLeft(), TRAVEL, 'linear');                     // 置いた瞬間にスッと発進
      await wait(TRAVEL+20);
      if(my!==token) return;
      setX(offRight(), 0);                                   // 左で消えて右外へワープ(待機位置)
    } finally {
      if(motor) motor.classList.remove('driving');          // 走り終え(or 中断)でブルブル停止
    }
  }

  // motor ソケットからの ON/OFF(状態変化時のみ反応)
  window.prarailMotor=function(on){
    on=!!on;
    if(on===inserted) return; inserted=on;
    token++;                                                 // 進行中シーケンスを無効化
    if(on){ runOnce(token); }                                // 挿した瞬間に一度だけ走る
    else  { setX(offRight(), 320, 'ease-in'); idleLoop(token); } // 抜いたら チラ見せへ戻す
  };

  // スピーカー演出のON/OFF。踊っているあいだはチラ見せを止め、終わったら(motor未挿入なら)再開。
  // motor 挿入中(走行制御中)は触らない＝走行を中断しない。
  window.prarailDancing=function(on){
    on=!!on; if(on===dancing) return; dancing=on;
    if(inserted) return;                                     // 走行制御中は介入しない(終了後にmotor側が再開)
    token++;                                                 // 進行中のチラ見せを無効化
    if(on) setX(offRight(), 320, 'ease-in');                 // 踊り中は引っ込めてチラ見せ停止
    else   idleLoop(token);                                  // 解除後はチラ見せ再開
  };

  idleLoop(token);                                           // 起動時(motor未挿入)はチラ見せから
  let rt; window.addEventListener('resize',()=>{ clearTimeout(rt); rt=setTimeout(()=>{
    if(!inserted) setX(offRight(), 0);                       // 待機中はリサイズで右外位置を補正
  }, 200); });
})();

// ---- 縁のマイコンボード群: ステージの縁をぐるりと囲む。デフォルト非表示。
//      スピーカーを挿すと1枚ずつ増えて出現し、音に合わせて各辺の進行方向へ時計回りに歩く。
//      抜くと1枚ずつ消え、最後の1枚はXに振ってからダンス姿に戻って消える。 ----
(function(){
  const stage=document.querySelector('.stage'); if(!stage) return;
  const host=document.querySelector('.dancers'); if(!host) return;
  const VARIANTS=4;
  const beat=60/DANCE_BPM;                 // 1拍の秒数(LED点滅・周回テンポの同期に使用)
  host.style.setProperty('--beat', beat.toFixed(3)+'s');
  document.body.style.setProperty('--beat', beat.toFixed(3)+'s');   // 画面全体の演出(party-fx)も同じ拍で脈打つ

  // 各ボード色のネオン発光色(ダークモードで全体が光る)。dancer1..4(赤/緑/黄/青)に対応。
  const GLOWS=['#ff5566','#44e58a','#ffb733','#55d6f2'];
  let dancers=[], ranks=[], count=0;
  const build=n=>{
    host.innerHTML=''; dancers=[];
    for(let i=0;i<n;i++){
      const d=document.createElement('div'); d.className='dancer';
      d.style.backgroundImage='url(images/dancer'+((i%VARIANTS)+1)+'.png)';
      d.style.setProperty('--glow', GLOWS[i%VARIANTS]);   // ダークモードの発光色(LED/ボードグローが参照)
      d.innerHTML='<span class="d-led"></span>';
      host.appendChild(d); dancers.push(d);
    }
    // 出現順をシャッフル(ランダムに散らして1枚ずつ増えていく)
    ranks=[...Array(n).keys()];
    for(let i=n-1;i>0;i--){ const j=(Math.random()*(i+1))|0; const t=ranks[i]; ranks[i]=ranks[j]; ranks[j]=t; }
    count=n;
  };

  // 矩形リング(x0,y0)-(x1,y1)の周長 f(0..1) の点。左上から時計回り(上→右→下→左)。
  const ptAt=(f,x0,y0,x1,y1)=>{
    const w=x1-x0, h=y1-y0, per=2*(w+h); let d=f*per;
    if(d<w) return [x0+d, y0]; d-=w;
    if(d<h) return [x1, y0+d]; d-=h;
    if(d<w) return [x1-d, y1]; d-=w;
    return [x0, y1-d];
  };
  // 周長 f での「進行方向(時計回りの接線)F」と「径方向(内向き)P」の単位ベクトル。
  // 各辺で前進/縦揺れの向きを回すために使う(上辺では F=右, P=下 で画面x/yと一致)。
  const dirAt=(f,x0,y0,x1,y1)=>{
    const w=x1-x0, h=y1-y0, per=2*(w+h); let d=f*per;
    if(d<w) return {fx:1,fy:0,px:0,py:1};    // 上辺: 前進=右 / 径=下
    d-=w;
    if(d<h) return {fx:0,fy:1,px:-1,py:0};   // 右辺: 前進=下 / 径=左
    d-=h;
    if(d<w) return {fx:-1,fy:0,px:0,py:-1};  // 下辺: 前進=左 / 径=上
    return {fx:0,fy:-1,px:1,py:0};           // 左辺: 前進=上 / 径=右
  };

  const tickerEl=document.querySelector('.ticker');
  let geom=null;
  const layout=()=>{
    const sr=stage.getBoundingClientRect();
    const W=sr.width, H=sr.height; if(!W||!H) return;
    const tickH=tickerEl?tickerEl.getBoundingClientRect().height:48;
    // 傾き(対角≈17px)＋縦揺れ(±BOB)のはみ出しぶんのマージン。これ未満だと見切れる。
    const M=30;
    // 上辺=電源レール(赤≈y14/青≈y78)の帯の中央(≈46)に収める。下辺=電光掲示板の上。左右=見切れ防止。
    const x0=M, y0=46, x1=W-M, y1=H-(tickH+M);
    if(x1<=x0||y1<=y0) return;
    const per=2*((x1-x0)+(y1-y0));
    // 周長に応じて枚数。モバイルは縦長で周長が伸び枚数が増えすぎるため、間隔を広く・上限を低くして間引く。
    const sp=BB_MOBILE()?120:76, nmin=BB_MOBILE()?8:12, nmax=BB_MOBILE()?18:40;
    const n=Math.max(nmin, Math.min(nmax, Math.round(per/sp)));
    if(n!==count) build(n);
    geom={x0,y0,x1,y1,n};
    // LED点滅の位相を位置でずらす(リングをきらめきが渡る)
    dancers.forEach((d,i)=>d.style.setProperty('--d', (-((i/n)*beat*6)).toFixed(3)+'s'));
  };

  // 輪として全体が回転: 全ボードの周回位置 f を時間で進める(リングに沿って循環)。
  // さらに各ボードを斜め(↗↙)方向に小さく揺らして「斜めに移動しながら」を添える。
  // 進行はスピーカー装着中(body.dance-on)だけ。位置は transform で更新(リフロー回避)。
  let orbT=0, last=0, revealT=0, waveT=0, fadeKicked=false, wasEndless=false;
  const TILT=-45;                    // dancer の傾き(度): 左下→右上(↗)を向く
  const BOB=10;                      // 径方向(縦)の揺れ幅(px)。毎拍 ±BOB で反転
  const REVEAL_PER=0.07;             // 基盤が1枚増える間隔(秒)。全部出るまで ≒ n*0.07 秒
  const ADV_FRAC=0.2;                // 前進量(スロット比)。前進は必ず「斜め(x+y)の拍」に束ねる
  const LEAD=0.06;                   // 視覚スナップを音より少し先行させる秒数
  const WAVE_DUR=0.5;                // 最後の1枚が「ぱらぱらっ」と振れて消えるまでの秒数(少し短め)
  const FLAP=0.085;                  // 1フラップの秒数(短い=キレよく速い)。/ ↔ \ をスナップ往復
  const FLAP_ANG=52;                 // 振れ角(度)。± で / と \ になりXを描く
  const FADE_BARS=4;                 // 踊り始めてから何小節でフェードアウトを始めるか(4/4拍子)
  const FADE_START=FADE_BARS*4*beat; // フェード開始時刻(秒): 4小節=16拍ぶん経ったら
  const MUSIC_FADE=6.0;              // 自動終了時の音楽フェードアウト秒数
  const OUT_DUR=4.0;                // 4小節後、全基盤が消えきるまでの秒数(枚数によらず一定=徐々に1枚ずつ減る)
  // 2拍くりかえし: ①斜め移動(前進=接線方向 + 縦揺れ反転) → ②縦だけ(径方向の反転のみ)。
  // = x単独(横移動だけ)のフレームを作らない。各辺で接線/径方向に回すので全周で時計回り。
  const animate=ts=>{
    if(!last) last=ts;
    const dt=Math.min(0.05,(ts-last)/1000); last=ts;
    const dancing=document.body.classList.contains('dance-on');
    const endless=document.body.classList.contains('dance-endless');   // スピーカーを最後にはめて完成=無限ループ
    if(geom){
      const {x0,y0,x1,y1,n}=geom;
      // 拍時計: 音(danceClock)優先、無ければ orbT(rAF累積)にフォールバック。音を止めた後も orbT で進み続ける。
      const dc = window.danceClock ? window.danceClock() : null;
      const clk = (dancing && dc!=null && dc>0) ? dc : orbT;
      if(dancing){
        orbT+=dt;
        if(endless){
          fadeKicked=false;                              // 無限中は自動終了させない
          revealT=Math.min(n*REVEAL_PER, revealT+dt);    // 全基盤を満タンで維持して踊り続ける
        } else {
          // 無限を抜けた直後(=完成が崩れた wasEndless)は即フェード。通常デモは4小節経過でフェード。
          if(!fadeKicked && (wasEndless || clk>=FADE_START)){
            fadeKicked=true; if(window.danceEnd) window.danceEnd(MUSIC_FADE);   // 音楽フェードアウト(一度だけ)
          }
          revealT = fadeKicked
            ? Math.max(0, revealT - dt*(n*REVEAL_PER)/OUT_DUR)   // OUT_DUR 秒で1枚ずつ消えきる
            : Math.min(n*REVEAL_PER, revealT+dt);                // フェード前は4小節まで1枚ずつ出現
        }
        waveT=0;
      }
      else {
        // 抜去時: 1枚ずつ減らす(出現より少し速く)。最後の1枚は手を振ってから(WAVE_DUR後)消す。
        orbT=0;          // 非ダンス時はリセット(次回開始時に音と同位相から)
        fadeKicked=false;
        const sh=Math.floor(revealT/REVEAL_PER);
        if(sh>=2){ revealT-=dt*2; waveT=0; }
        else if(sh===1){ waveT+=dt; if(waveT>WAVE_DUR) revealT-=dt*2; }
        else waveT=0;
        revealT=Math.max(0, revealT);
      }
      wasEndless=endless;   // 次フレームで「無限を抜けた瞬間」を捉えるため
      const shown=Math.floor(revealT/REVEAL_PER);
      const bi=Math.floor((clk+LEAD)/beat);        // 現在の拍。LEADぶん先行させてキレを出す
      const adv=Math.floor(bi/2)*ADV_FRAC;         // 前進(x+y=斜め)を偶数拍=キックに合わせる。奇数拍は縦だけ
      const farewell = !dancing && shown===1;      // 最後の1枚(rank0)がバイバイする局面
      for(let i=0;i<dancers.length;i++){
        const d=dancers[i];
        const vis = ranks[i] < shown;              // shown が増減: 出現も4小節後の消失も、ランダム順(ranks)で1枚ずつ
        d.style.opacity = vis ? '1' : '0';
        if(!vis) continue;
        const f=((((i+adv)%n)+n)%n)/n;             // 前進は base(リング位置)で表現=斜めの拍に必ず束ねる
        const p=ptAt(f,x0,y0,x1,y1);
        const isBye = farewell && ranks[i]===0;
        d.classList.toggle('bye', isBye);            // パーティモード(ダーク)で光ったままお手ふりさせるための印
        if(isBye){
          // ぱらぱらっ: 下3分目あたりを軸に / ↔ \ を素早くスナップ往復=Xを描いてキレよく消える
          // ぱらぱらっと振り、最後はダンス時の傾き(↗=TILT)に戻して終える(0°=水平=横倒しを避ける)
          const ang=(waveT < WAVE_DUR-FLAP) ? (Math.floor(waveT/FLAP)%2 ? FLAP_ANG : -FLAP_ANG) : TILT;
          d.style.transformOrigin='50% -35%';         // 支点をバーより上に
          d.style.transform='translate('+p[0].toFixed(1)+'px,'+p[1].toFixed(1)+'px) rotate('+ang+'deg)';
          continue;
        }
        d.style.transformOrigin='50% 50%';           // 通常は中心軸(離脱演出から復帰)
        const dir=dirAt(f,x0,y0,x1,y1);
        // 縦揺れ(径方向)を毎拍反転＋隣どうしでも反転(片方が上なら隣は下=違い違い)
        const perp=dancing ? (((bi+i)%2)?-1:1)*BOB : 0;
        const sx=perp*dir.px, sy=perp*dir.py;
        d.style.transform='translate('+(p[0]+sx).toFixed(1)+'px,'+(p[1]+sy).toFixed(1)+'px) rotate('+TILT+'deg)';
      }
    }
    requestAnimationFrame(animate);
  };
  layout();
  requestAnimationFrame(animate);
  if(document.fonts&&document.fonts.ready) document.fonts.ready.then(layout);
  let t; window.addEventListener('resize',()=>{ clearTimeout(t); t=setTimeout(layout,200); });
})();

// ---- [未配線] 落下リセット: 挿さっている部品が重力でバラバラ落ちてボード底に積もる(=全ギミック解除)。
//      落ちる向きはPCの場合真下、モバイルの場合デバイスの傾き(nx)。
(function(){
  const stage=document.querySelector('.stage'); if(!stage) return;
  // 重力の左右の傾き(-1..1)。PCは常に真下(0)に落とす。モバイルだけ端末の傾きで横へ倒す。
  let nx=0;
  const clamp=v=>v<-1?-1:v>1?1:v;
  const onOrient=e=>{ if(e.gamma!=null) nx=clamp(e.gamma/30); };
  // 端末の傾きを購読(許可不要な環境のみ)。iOS13+ は要 requestPermission だが、まだトリガ未実装で
  // 機能が眠っているため、不用意な許可ダイアログは出さない。スイッチを付けるとき一緒に繋ぐ。
  const D=window.DeviceOrientationEvent;
  if(D && typeof D.requestPermission!=='function') window.addEventListener('deviceorientation', onOrient);

  // 落下: 挿さっている部品それぞれに初速(軽い跳ね＋ばらけ＋回転)を与え、重力で落とす。
  // 重力ベクトルは傾き nx ぶん横へ倒れる(端末を傾けた方へ転がり落ちる)。
  // 画面外には出さない: ボード底(電光掲示板の上)=床、左右=壁で跳ね返し、底に積もって止まる。
  let falling=false;
  window.boardReset=function(){
    if(falling) return;
    // バッテリーはダークモード時(電源レールに挿さって点灯中)だけ据え置き。それ以外は他と同様に落とす。
    const dark=document.body.classList.contains('dark');
    const parts=[...document.querySelectorAll('[data-part]')]
      .filter(el=>!(el.dataset.part==='battery' && dark));
    if(!parts.length) return;
    falling=true;
    const sw=stage.clientWidth, sh=stage.clientHeight;
    const ticker=document.querySelector('.ticker');
    const floorY=sh-((ticker&&ticker.offsetHeight)||54)-2;     // 床の高さ(電光掲示板の上端)
    const M=6;                                                 // 壁の内側マージン
    // base=現在位置(offsetは transform の影響を受けない) / x,y,a=そこからの変位
    const items=parts.map(el=>({ el,
      baseL:el.offsetLeft, baseT:el.offsetTop, w:el.offsetWidth, h:el.offsetHeight,
      x:0, y:0, a:0,
      vx:(Math.random()*2-1)*2.4,            // 横のばらけ
      vy:-(2+Math.random()*4),               // いったん上に跳ねてから落ちる(弾かれた感)
      va:(Math.random()*2-1)*9,              // 回転(タンブル)
      bounced:false, rest:false }));
    items.forEach(it=>{ it.el.style.transition='none'; it.el.style.zIndex=40; });
    const G=0.9, MAXFALL=1.0;                // 重力の強さ / 横倒しの最大(rad≈57°)
    let fr=0;
    (function fall(){
      const rad=nx*MAXFALL, gx=Math.sin(rad)*G, gy=Math.cos(rad)*G;
      // 1) 動きを積分 + 壁/床(1バウンド→整定)
      items.forEach(it=>{
        if(it.rest) return;
        it.vx+=gx; it.vy+=gy; it.x+=it.vx; it.y+=it.vy; it.a+=it.va;
        const xMin=-it.baseL+M, xMax=sw-it.w-it.baseL-M;       // 左右の壁で跳ね返す
        if(it.x<xMin){ it.x=xMin; it.vx=-it.vx*0.5; }
        if(it.x>xMax){ it.x=xMax; it.vx=-it.vx*0.5; }
        const yFloor=floorY-it.baseT-it.h;                     // 床に接する y
        if(it.y>=yFloor){
          it.y=yFloor;
          if(!it.bounced && it.vy>2){                          // 最初の接地だけ1回バウンド
            it.vy=-it.vy*0.42; it.vx*=0.7; it.va*=0.5; it.bounced=true;
          }else{                                               // 着地後の整定(スナップさせず数フレームで落ち着かせる)
            it.vy=0;                                           // 縦は床で止める
            it.vx*=0.55; it.va*=0.5;                           // 横と回転は強めの摩擦でキレよく減衰
            it.a+=(0-it.a)*0.35;                               // 角度は水平へイージング
            if(Math.abs(it.vx)<0.25 && Math.abs(it.a)<1.2){    // 充分遅くなったら静止
              it.rest=true; it.vx=it.va=0; it.a=0;
            }
          }
        }
      });
      // 2) 部品どうしの衝突(AABB): 重なりを押し離し、当たった向きへ少しバウンド。重ならないようにする。
      for(let i=0;i<items.length;i++) for(let j=i+1;j<items.length;j++){
        const A=items[i], B=items[j];
        const aL=A.baseL+A.x, aT=A.baseT+A.y, bL=B.baseL+B.x, bT=B.baseT+B.y;
        const ox=Math.min(aL+A.w,bL+B.w)-Math.max(aL,bL);     // 重なり幅
        const oy=Math.min(aT+A.h,bT+B.h)-Math.max(aT,bT);     // 重なり高
        if(ox>0.5 && oy>0.5){
          if(ox<oy){                                          // 横の重なりが浅い → 左右に押し離す
            const dir=(aL+A.w/2)<=(bL+B.w/2)?1:-1, s=ox/2;
            A.x-=s*dir; B.x+=s*dir;
            const imp=Math.min(2.2, s*0.3+0.4);               // 少しバウンド
            A.vx-=imp*dir; B.vx+=imp*dir;
          }else{                                              // 縦の重なりが浅い → 上下に押し離す(上に乗る)
            const dir=(aT+A.h/2)<=(bT+B.h/2)?1:-1, s=oy/2;
            A.y-=s*dir; B.y+=s*dir; A.vy*=0.3; B.vy*=0.3;
          }
          A.rest=B.rest=false;                                // ぶつかったら起こして再整定
        }
      }
      // 3) 壁/床へ再クランプ + 反映 + 残り判定
      let moving=0;
      items.forEach(it=>{
        const xMin=-it.baseL+M, xMax=sw-it.w-it.baseL-M;
        if(it.x<xMin) it.x=xMin; else if(it.x>xMax) it.x=xMax;
        const yFloor=floorY-it.baseT-it.h;
        if(it.y>yFloor) it.y=yFloor;
        if(!it.rest) moving++;
        it.el.style.transform='translate('+it.x.toFixed(1)+'px,'+it.y.toFixed(1)+'px) rotate('+it.a.toFixed(1)+'deg)';
      });
      if(moving && ++fr<600) requestAnimationFrame(fall);      // 600フレームで打ち切り(安全弁)
      else {
        // 着地位置を left/top に焼き込んで確定(画面内に残す・ドラッグも続行可)。保存もする。
        items.forEach(it=>{
          const L=Math.round(it.baseL+it.x), T=Math.round(it.baseT+it.y);
          it.el.style.transform=''; it.el.style.transition=''; it.el.style.zIndex='';
          it.el.style.left=L+'px'; it.el.style.top=T+'px'; it.el.style.right='auto'; it.el.style.bottom='auto';
          document.cookie='pos_'+it.el.dataset.part+'=;path=/;max-age=0';   // 床に散った=未装着なので記憶しない
        });
        falling=false;
      }
    })();
  };
  // トリガ(スイッチ/傾きセンサー部品)は未実装。付ける時は window.boardReset() を呼ぶ。
  // 動作確認したいときは DevTools コンソールで boardReset() を実行する。
})();

// ---- 7セグ カウントダウン表示部品: 会期(2026.10.31)までの残り日数 ----
//   .bb-seg7(HTML)に中身を流し込む。普段は消灯(=画像のまま)、専用ソケットに挿すと .lit が付いて点灯。
//   7seg-2.png(3桁・全消灯)を地に、残り日数の点灯セグメントを重ね、左上にCOUNTDOWNラベル(透明)を置く。
(function(){
  const el=document.querySelector('.bb-seg7'); if(!el) return;
  const TARGET=new Date('2026-10-31T00:00:00+09:00');
  // 数字→点灯セグメント(a=上,b=右上,c=右下,d=下,e=左下,f=左上,g=中)
  const SEG={'0':'abcdef','1':'bc','2':'abged','3':'abgcd','4':'fgbc','5':'afgcd','6':'afgecd','7':'abc','8':'abcdefg','9':'abcdfg',' ':''};
  // 各セグメントの実形状: 画像から連結成分で抽出した凸包。点灯を印刷セグメントへ正確に重ねる(近似でなく実測)。
  // 各値は [dx(桁中心cx基準), y(絶対px)]。100日以上=3桁(7seg-2) / 100日未満=2桁(7seg-1)で別実測。
  const GEO={
    3:{ img:'images/7seg-2.png', W:330, H:163, dw:108, cells:[60,166,270],
      mask:[[-37,56],[-36,31],[-27,21],[27,21],[36,31],[36,128],[26,139],[-27,139],[-36,129],[-37,117]], segs:{
      a:[[-27,28],[-24,24],[24,24],[26,27],[26,29],[21,34],[-22,34]],
      b:[[23,44],[24,38],[25,36],[29,32],[30,32],[33,34],[33,72],[30,75],[28,75],[23,70]],
      c:[[23,89],[26,86],[29,84],[30,84],[33,86],[33,125],[30,128],[28,127],[23,122]],
      d:[[-26,130],[-24,128],[-21,126],[21,126],[25,130],[25,133],[23,136],[-24,136],[-26,133]],
      e:[[-33,87],[-31,85],[-29,85],[-24,90],[-24,118],[-25,122],[-27,125],[-30,128],[-31,128],[-33,126]],
      f:[[-33,34],[-31,32],[-29,32],[-25,37],[-24,51],[-24,69],[-25,71],[-29,75],[-31,75],[-33,73]],
      g:[[-26,79],[-23,76],[-21,75],[2,74],[12,74],[21,75],[25,79],[25,81],[21,85],[-16,85],[-22,84],[-25,82],[-26,81]] } },
    2:{ img:'images/7seg-1.png', W:211, H:165, dw:68, cells:[56.5,154],
      mask:[[-35,32],[-28,24],[-25,21],[26,21],[29,24],[35,31],[35,131],[26,141],[-25,141],[-35,131]], segs:{
      a:[[-25,28],[-22,24],[23,24],[26,27],[26,30],[21,35],[-18,35],[-21,34],[-23,32],[-25,29]],
      b:[[23,39],[29,33],[30,33],[32,34],[32,75],[29,77],[23,71]],
      c:[[23,91],[29,85],[30,85],[32,87],[32,128],[30,130],[29,130],[25,127],[23,124]],
      d:[[-24,133],[-20,128],[21,128],[23,130],[25,133],[25,135],[23,138],[-22,138],[-24,135]],
      e:[[-32,88],[-31,87],[-29,86],[-28,86],[-26,87],[-23,90],[-23,125],[-28,130],[-29,130],[-32,128]],
      f:[[-32,35],[-29,33],[-27,33],[-25,35],[-23,38],[-23,72],[-28,77],[-29,77],[-32,74]],
      g:[[-25,81],[-22,77],[-18,75],[21,75],[25,80],[25,81],[24,83],[22,86],[-21,86],[-25,82]] } },
  };
  const css=`
  .bb-seg7{user-select:none;-webkit-user-select:none;-webkit-touch-callout:none;}  /* ドラッグ時の青い選択ハイライトを抑止 */
  .bb-seg7 .mod{position:relative;width:100%;height:100%;line-height:0;}
  .bb-seg7 .mod>img{display:block;width:100%;height:100%;image-rendering:pixelated;-webkit-user-drag:none;user-drag:none;}
  .bb-seg7 svg.segs{position:absolute;inset:0;width:100%;height:100%;}
  .bb-seg7 .m{fill:#403c35;opacity:0;}                                   /* 点灯時、桁の外形を地色で覆ってOFFセグを隠す(実物の暗いOFF感) */
  .bb-seg7.lit .m{opacity:1;}
  .bb-seg7 .s{fill:#ff5a4d;opacity:0;}                                   /* 消灯時は非表示=画像の地のまま。点灯色=明るめの赤 */
  .bb-seg7.lit .s.on{opacity:1;filter:drop-shadow(0 0 .7px #ff8579) drop-shadow(0 0 1.8px rgba(255,90,70,.34));}  /* 点いた赤だけ薄く発光 */
  /* COUNTDOWNラベル */
  .bb-seg7 .cd-lab{position:absolute;left:-2px;top:-11px;font-family:'Jersey 10','Micro 5',monospace;
    font-size:10px;letter-spacing:2px;line-height:1;color:var(--ink);opacity:.8;white-space:nowrap;pointer-events:none;}
  `;
  const st=document.createElement('style'); st.textContent=css; document.head.appendChild(st);
  let rects=[], curN=0;
  function build(n){                       // n桁ぶんのモジュール(画像+点灯セグメント)を組み立てる
    const G=GEO[n]; let mhtml='', shtml='';
    G.cells.forEach((cx,i)=>{
      mhtml+=`<polygon class="m" points="${G.mask.map(([dx,y])=>(cx+dx)+','+y).join(' ')}"/>`;  // 桁の外形を地色で覆うマスク(印刷OFFセグ＋AA縁を消す。下層)
      'abcdefg'.split('').forEach(s=>{
        const pts=G.segs[s].map(([dx,y])=>(cx+dx)+','+y).join(' ');
        shtml+=`<polygon class="s" data-i="${i}" data-s="${s}" points="${pts}"/>`; }); });     // 点灯赤(上層)
    const oldW=el.offsetWidth;             // 幅変更の前に現在幅を控える
    el.style.width=G.dw+'px';              // モジュール幅は桁数で変わる(高さはCSS固定=桁サイズ一定)
    const lf=parseFloat(el.style.left);    // 幅が変わったら left を半分補正して「中心」を保つ(ソケットと揃う)
    if(!isNaN(lf) && oldW && oldW!==G.dw) el.style.left=(lf+(oldW-G.dw)/2)+'px';
    el.innerHTML='<div class="mod"><span class="cd-lab">COUNTDOWN</span><img src="'+G.img+'" alt="">'
      +'<svg class="segs" viewBox="0 0 '+G.W+' '+G.H+'">'+mhtml+shtml+'</svg></div>';
    rects=[...el.querySelectorAll('.s')]; curN=n;
    document.body.classList.toggle('seg7-2', n===2);   // ソケット枠も2桁/3桁を切替
  }
  function render(){
    const days=Math.max(0,Math.ceil((TARGET-new Date())/86400000));
    const n=days>=100?3:2;                 // 100日未満で2桁モジュールへ
    if(n!==curN) build(n);
    const str=String(days).padStart(n,' ');
    rects.forEach(r=>{ const ch=str[+r.dataset.i]||' ';
      r.classList.toggle('on', (SEG[ch]||'').includes(r.dataset.s)); });
  }
  render(); setInterval(render, 60000);
})();

// ボタンの hover 効果音: E6→C7 へ上昇する短い跳ね。triangle をローパス3000で丸める家系の音色。
// hover は連発し高音で耳に通りやすいので、低い音量(0.085)で控えめに鳴らす。
(function(){
  const pico=()=>{ try{ const c=window.audioCtx&&window.audioCtx(); if(!c) return;
    const t=c.currentTime;
    const o=c.createOscillator(), g=c.createGain(); o.type='triangle';
    o.frequency.setValueAtTime(1319,t);                       // E6
    o.frequency.exponentialRampToValueAtTime(2093,t+0.05);    // C7 へ上昇
    g.gain.setValueAtTime(0.0001,t); g.gain.exponentialRampToValueAtTime(0.085,t+0.012);
    g.gain.exponentialRampToValueAtTime(0.0001,t+0.10);       // 余韻を残さず短く切る
    const lp=c.createBiquadFilter(); lp.type='lowpass'; lp.frequency.value=3000; lp.Q.value=1;
    o.connect(g); g.connect(lp); lp.connect(c.destination); o.start(t); o.stop(t+0.11);
  }catch(e){} };
  document.querySelectorAll('.button-icon').forEach(btn=>{
    btn.addEventListener('pointerenter', e=>{ if(e.pointerType==='touch') return; pico(); }); // タップでは鳴らさない
  });
})();
