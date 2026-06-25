const rnd=(a,b)=>a+Math.random()*(b-a);

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
  // ひと粒を一瞬光らせる。
  const kira=d=>{
    if(!d || d.classList.contains('kira')) return;
    d.classList.add('kira');
    d.addEventListener('animationend',()=>d.classList.remove('kira'),{once:true});
  };
  const pick=()=>dots[(Math.random()*dots.length)|0];
  // 環境演出: 1粒ずつ、あちこちの LED を順に渡り歩く(同時多発させない)。
  (function loop(){
    kira(pick());
    setTimeout(loop, 560+Math.random()*900);   // ≈0.56〜1.46s 間隔
  })();
  // モーター連動フック
  window.rubyGlint=function(){
    kira(pick());
    if(Math.random()<0.4) setTimeout(()=>kira(pick()), 90+Math.random()*120);
  };
})();

// ===== 部品スナップ共有定義(ドラッグ／回路の両方で使用) =====
const BB_GRID=24;
// 背景レールの水平シフト量(px)。ルビー先端に穴列を合わせるため背景をずらした量を
// ここに一元化し、部品/ソケット/電光掲示板の脚など全スナップの x がこれに追従する。
let BB_BGX=0;
const BB_PIN={
  // chip=上下4ピンのみ穴基準(左右は飾り) / battery=±端子 / motor=2リード
  chip:[[0.2925,0.003],[0.687,0.003],[0.687,0.979],[0.2925,0.979]],
  battery:[[0.4805,0.005],[0.4805,0.984]],
  motor:[[0.206,0.9785],[0.769,0.9785]],
};
const BB_SNAPOFF={ chip:[0,12], motor:[0,12] };   // 12=穴上(12+24n) / 0=穴間(24n) / [x,y]=軸別
const BB_NUDGE={ motor:[1,2] };                    // スナップ後の見た目微調整[x,y]px
const bbSnapP=(v,part,ax)=>{ const o=BB_SNAPOFF[part];
  // x軸(ax=0)は背景シフト量 BB_BGX ぶん原点をずらして、見た目の穴列に合わせる
  const off=(Array.isArray(o)?o[ax]:(o!=null?o:12)) + (ax===0?BB_BGX:0);
  return Math.round((v-off)/BB_GRID)*BB_GRID+off; };
const bbAnchor=part=>{ const p=BB_PIN[part]; if(!p) return [0.5,0.5];
  let ax=0,ay=0; p.forEach(q=>{ax+=q[0];ay+=q[1];}); return [ax/p.length, ay/p.length]; };
// (left,top: ステージ基準px)→ 接点を穴に合わせたスナップ位置[x,y]
function bbSnapPos(part, left, top, W, H, stageH){
  const a=bbAnchor(part), px=left+a[0]*W, py=top+a[1]*H;
  const x=bbSnapP(px,part,0)-a[0]*W;
  let y;
  if(part==='battery'){
    const cyEl=top+H/2, railY=(cyEl<96)?45:(cyEl>stageH-96)?(stageH-46):null; // 上/下レール帯なら中央へ
    y=(railY!=null)?(railY-H/2):(bbSnapP(py,part,1)-a[1]*H);
  } else { y=bbSnapP(py,part,1)-a[1]*H; }
  const nd=BB_NUDGE[part]||[0,0];
  return [x+nd[0], y+nd[1]];
}

// ===== ルビー整列 + 背景シフト(BB_BGX)の一元処理 =====
// 縦: ルビーを最寄りの穴行へ寄せる。横: ルビー先端(=画像の水平中央)のXに穴列が来るよう
// 背景を水平シフトし、その量を BB_BGX に保存(部品/ソケット/脚の x スナップが追従)。
function bbApplyGridShift(){
  const stage=document.querySelector('.stage');
  const ruby=document.querySelector('.ruby-led');
  if(!stage||!ruby) return;
  const HOLE0=12.5, PITCH=24;
  const snap=v=>HOLE0+PITCH*Math.round((v-HOLE0)/PITCH);
  const BASE='translate(-50%, calc(-50% + clamp(26px, 5vh, 52px)))'; // CSS と同じ中央配置
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
  const setC=(k,v)=>{document.cookie=k+'='+v+';path=/;max-age=31536000';};
  const getC=k=>{const m=document.cookie.match('(?:^|; )'+k+'=([^;]*)');return m?m[1]:null;};
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
  // 現在位置(left,top)から接点を穴に合わせたスナップ位置[x,y](共有の bbSnapPos を使用)
  const computeSnap=(el,left,top)=>bbSnapPos(el.dataset.part, left, top, el.offsetWidth, el.offsetHeight, stage.getBoundingClientRect().height);
  document.querySelectorAll('[data-part]').forEach(el=>{
    const id=el.dataset.part; if(!id) return;
    // 保存位置を復元(あれば inline の初期位置を上書き)。無ければ初期位置を穴にスナップ
    const saved=getC('pos_'+id);
    if(saved){ const p=saved.split(',').map(Number);
      el.style.left=p[0]+'px'; el.style.top=p[1]+'px'; el.style.right='auto'; el.style.bottom='auto'; }
    else if(el.dataset.part){
      const r=el.getBoundingClientRect(), sr=stage.getBoundingClientRect();
      // 3部品は chip(=L-chika ソケットの列)を起点に、左→右へ chip,motor,battery と並べる
      const TRAY_DX={chip:0, motor:72, battery:132};
      const colX=()=>{ const lg=document.querySelector('.title .prk'); if(!lg) return r.left-sr.left;
        return lg.getBoundingClientRect().right-stage.getBoundingClientRect().left+16+(TRAY_DX[id]||0); };
      const [fx,fy]=computeSnap(el, colX(), r.top-sr.top);
      el.style.left=fx+'px'; el.style.top=fy+'px'; el.style.right='auto'; el.style.bottom='auto';
      // ロゴはWebフォント(Bitcount)読込で幅が変わる→フォント確定後に列を再スナップ(未操作時のみ)。
      // 1回計算だと実行時のフォント未適用幅で1セルずれることがあるため。
      if(document.fonts && document.fonts.ready){
        document.fonts.ready.then(()=>requestAnimationFrame(()=>{
          if(getC('pos_'+id)||dragging||moved) return;
          const [gx]=computeSnap(el, colX(), parseFloat(el.style.top)||0);
          el.style.left=gx+'px';
        }));
      }
    }
    let sx,sy,ox,oy,moved=false,dragging=false;
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
        el.style.left=fx+'px'; el.style.top=fy+'px';
        setC('pos_'+id, fx+','+fy);
        dropPop(); // 穴に「ぱちっ」
      }

    };
    el.addEventListener('pointerup',end);
    el.addEventListener('pointercancel',end);
    // ドラッグ直後のクリック(トグル/アクション発火)を抑制
    el.addEventListener('click',e=>{ if(moved){ e.preventDefault(); e.stopPropagation(); moved=false; } },true);
  });
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
  // 各ソケット: 所定の部品(part)が所定の位置(place)に挿さる演出ON。
  // ソケットは Ruby を中心に1列に並べる。左から: speaker → (Ruby) → motor → chip。
  // いずれも scene を基準に置き、Ruby の縦中心(rubyCY)に各部品の中心を合わせる。
  const cx  =(a,sr)=>a.left-sr.left+a.width/2;     // Ruby の水平中心(scene中心)
  const rubyCY=(a,sr)=>{ if(rubyLed){ const r=rubyLed.getBoundingClientRect(); return r.top-sr.top+r.height/2; } return a.top-sr.top+a.height/2; };
  const rowTop=(a,sr,h)=>rubyCY(a,sr)-h/2;         // 高さhの部品をRuby縦中心に合わせた上端Y
  const SOCKETS=[
    // モーター → Ruby の右 → 挿した瞬間にプラレールが右→左へ一度走り抜ける(通過音つき)。
    // 挿入前の待機/チラ見せ・発進・帰還はプラレールコントローラ(window.prarailMotor)が担う。
    scene && { part:'motor',   anchor:scene, w:44, h:57,
               place:(a,sr)=>({ sx:cx(a,sr)+104, sy:rowTop(a,sr,57) }),
               apply:on=>{ if(window.prarailMotor) window.prarailMotor(on); } },
    // チップ → モーターの右(行の右端) → PicoRubyKaigi がLチカ。
    scene && { part:'chip',    anchor:scene, w:56, h:56,
               place:(a,sr)=>({ sx:cx(a,sr)+204, sy:rowTop(a,sr,56) }),
               apply:on=>body.classList.toggle('fx-lchika-off', !on) },
    // バッテリー → 電源レール(赤+/青-)をまたぐ → ダークモード(暗闇でボードが光る)。位置は据え置き。
    {            part:'battery', anchor:stage, w:27, h:46,
               place:(a,sr)=>({ sx:a.width-180, sy:24 }), // レール・右寄り(中心<96でレール中央へスナップ)
               apply:on=>body.classList.toggle('dark', on) },
  ].filter(Boolean);
  SOCKETS.forEach(s=>{ s.el=document.createElement('div'); s.el.className='circuit-slot circuit-slot--'+s.part; stage.appendChild(s.el); s.was=false; s.wasTouch=false; s.wasWrong=false; s.apply(false); });
  function frame(){
    const sr=stage.getBoundingClientRect();
    SOCKETS.forEach(s=>{
      const a=s.anchor.getBoundingClientRect();
      const p0=s.place(a,sr); const W=s.w, H=s.h;
      // ソケット枠を「部品が実際に収まる格子位置」に合わせる
      const [sx,sy]=bbSnapPos(s.part, p0.sx, p0.sy, W, H, sr.height);
      s.el.style.left=sx+'px'; s.el.style.top=sy+'px'; s.el.style.width=W+'px'; s.el.style.height=H+'px';
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
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
})();

// ---- イントロ誘導: 一定時間どの部品も操作されなければ、最初のアクション=チップの真上に矢印を薄く点滅 ----
(function(){
  const stage=document.querySelector('.stage'); if(!stage) return;
  const chip=document.querySelector('.bb-chip'); if(!chip) return;
  const DELAY=4000;   // 4秒どの部品も操作されなければ矢印を出す
  let interacted=false, arrow=null;
  const hide=()=>{ if(arrow){ arrow.remove(); arrow=null; } document.body.classList.remove('intro-hint'); };
  const place=()=>{ if(!arrow) return;
    const r=chip.getBoundingClientRect(), sr=stage.getBoundingClientRect();
    arrow.style.left=(r.left-sr.left+r.width/2)+'px';
    arrow.style.top=(r.top-sr.top-40)+'px';
  };
  document.querySelectorAll('[data-part]').forEach(el=>
    el.addEventListener('pointerdown',()=>{ interacted=true; hide(); }));
  setTimeout(()=>{
    if(interacted) return;
    document.body.classList.add('intro-hint');   // スロットの主張を上げる
    arrow=document.createElement('div');
    arrow.className='intro-arrow';
    // x,yとも半ドット解像度(2=1ドット)。幅: 段1=7 / 段2=5 / 段3=3 / 先端=2 ドット。高さ: 1.5 / 1.5 / 1 / 1 ドット
    arrow.innerHTML='<svg width="28" height="20" viewBox="0 0 14 10" preserveAspectRatio="none" shape-rendering="crispEdges">'
      +'<rect x="0" y="0" width="14" height="3"/>'
      +'<rect x="2" y="3" width="10" height="3"/>'
      +'<rect x="4" y="6" width="6" height="2"/>'
      +'<rect x="5" y="8" width="4" height="2"/></svg>';
    stage.appendChild(arrow);
    place();
  }, DELAY);
  window.addEventListener('resize', place);
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

// ---- ルビー先端のXに背景の穴列を合わせる(共有の bbApplyGridShift を使用) ----
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

  // チラ見せ: motor が挿さるまで、不定間隔でヘッドを出し入れ
  async function idleLoop(my){
    while(my===token && !inserted){
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

  idleLoop(token);                                           // 起動時(motor未挿入)はチラ見せから
  let rt; window.addEventListener('resize',()=>{ clearTimeout(rt); rt=setTimeout(()=>{
    if(!inserted) setX(offRight(), 0);                       // 待機中はリサイズで右外位置を補正
  }, 200); });
})();
