const cubes=['images/cube1.png','images/cube2.png','images/cube3.png','images/cube4.png'];
const rnd=(a,b)=>a+Math.random()*(b-a);

// floating cubes around the logo
document.querySelectorAll('.title').forEach(title=>{
  const spots=[[-4,20],[-8,64],[101,16],[106,58],[44,-16],[70,-12]];
  spots.forEach((s,i)=>{
    const c=document.createElement('img'); c.className='logo-cube'; c.src=cubes[i%4]; c.alt='';
    c.style.cssText=`left:${s[0]}%;top:${s[1]}%;width:${(14+Math.random()*12)|0}px;`+
      `--fx:${rnd(-60,60)|0}px;--fy:${rnd(-60,60)|0}px;--d:${rnd(3,4.5).toFixed(2)}s;--dl:${(-rnd(0,3)).toFixed(2)}s`;
    title.appendChild(c);
  });
});

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

// assembling cubes + sparkles around the ruby
document.querySelectorAll('.scene').forEach(scene=>{
  for(let i=0;i<12;i++){
    const img=document.createElement('img'); img.className='cube'; img.alt=''; img.src=cubes[i%4];
    img.style.cssText=`left:${rnd(30,68)}%;top:${rnd(4,40)}%;width:${rnd(14,28)|0}px;`+
      `--dx:${rnd(-90,90)|0}px;--dy:${rnd(-150,-45)|0}px;--ex:${rnd(-70,70)|0}px;--ey:${rnd(-120,-35)|0}px;`+
      `--dur:${rnd(3.6,5).toFixed(2)}s;--delay:${(-rnd(0,5)).toFixed(2)}s`;
    scene.appendChild(img);
  }
  for(let i=0;i<4;i++){
    const s=document.createElement('span'); s.className='sparkle';
    s.style.cssText=`left:${rnd(30,68)}%;top:${rnd(4,38)}%;--sd:${rnd(1.6,3).toFixed(2)}s;animation-delay:${(-rnd(0,3)).toFixed(2)}s`;
    scene.appendChild(s);
  }
});

// ruby: a tall sparkle streaks left->right across the lower-middle edges,
// then the upper-right facet glints. Then a pause, and the cycle repeats.
(function(){
  const svg=document.querySelector('.ruby-facets');
  if(!svg) return;
  const SVGNS='http://www.w3.org/2000/svg';
  const spark=svg.querySelector('.spark');
  const faces=[...svg.querySelectorAll('.facet')]; // サイクルごとにこの中から1面をランダムに光らせる
  // comet trail: a pool of small square dots. head=大きく濃い, tail=小さく薄い
  spark.removeAttribute('transform'); // 各ドットを viewBox 絶対座標で配置する
  spark.style.opacity='1';            // 表示は trailG / flashG 側の opacity で制御
  const N=18;            // 尾を構成するドット数
  const HEAD_SZ=16, TAIL_SZ=3; // 頭/尾のドットの大きさ(viewBox単位)
  const TRAIL_LEN=260;   // 尾の最大長(距離)。頭の位置-この長さ が尾の末端
  const trailG=document.createElementNS(SVGNS,'g'); // 尾(ドット列)
  trailG.style.opacity='0';
  spark.appendChild(trailG);
  const dots=[];
  for(let i=0;i<N;i++){
    const r=document.createElementNS(SVGNS,'rect');
    trailG.appendChild(r); dots.push(r);
  }
  // 終点の「チカッ」= ドット絵のきらり(中心 + 上下左右に長い光条 + 斜めに短い光条)
  const AST=[[0,0],                                                  // 中心
            [0,-1],[0,-2],[0,-3],[0,-4],[0,-5],                      // 上(長)
            [0,1],[0,2],[0,3],[0,4],[0,5],                           // 下(長)
            [-1,0],[-2,0],[-3,0],[-4,0],[-5,0],                      // 左(長)
            [1,0],[2,0],[3,0],[4,0],[5,0],                           // 右(長)
            [1,1],[2,2],[-1,1],[-2,2],[1,-1],[2,-2],[-1,-1],[-2,-2]]; // 斜め(短)
  const AU=7; // アスタリスクのセルサイズ(ドット絵)
  const flashG=document.createElementNS(SVGNS,'g');
  flashG.style.opacity='0';
  AST.forEach(([cx,cy])=>{
    const r=document.createElementNS(SVGNS,'rect');
    r.setAttribute('x',cx*AU-AU/2); r.setAttribute('y',cy*AU-AU/2);
    r.setAttribute('width',AU); r.setAttribute('height',AU);
    flashG.appendChild(r);
  });
  spark.appendChild(flashG);
  // path along the lower-middle edges: left shoulder -> girdle -> right shoulder
  const P={SL:[20,357],M1:[293,478],M2:[792,478],SR:[1066,352]};
  const route=['SL','M1','M2','SR'];
  const cum=[0];
  for(let i=0;i<route.length-1;i++){const a=P[route[i]],b=P[route[i+1]];cum.push(cum[i]+Math.hypot(b[0]-a[0],b[1]-a[1]));}
  const total=cum[cum.length-1];
  const SEG3_D=cum[2]; // 3本目の線(GR→SR)に入る距離
  const pointAt=d=>{ // distance (clamped) -> [x,y] along the open path
    d=Math.max(0,Math.min(total,d));
    let i=0; while(i<route.length-2 && cum[i+1]<=d) i++;
    const a=P[route[i]],b=P[route[i+1]],f=(d-cum[i])/(cum[i+1]-cum[i]);
    return [a[0]+(b[0]-a[0])*f, a[1]+(b[1]-a[1])*f];
  };
  // 2段階の速度: 前半はゆっくり、後半は「はやい」スピード。止まらずに終点まで進む
  const SLOW_FRAC=0.50;            // ゆっくり進む距離の割合(前半)
  const T_SLOW=SLOW_FRAC*640;      // その区間の所要時間(遅い=以前の640相当)
  const T_FAST=(1-SLOW_FRAC)*360;  // 残り区間(はやい=以前の360相当)
  const SWEEP=T_SLOW+T_FAST;       // 0→終点まで動く総時間(とどまらない)
  const CYCLE=3400;                // 1サイクルの長さ(走り→ひと呼吸)
  const FLASH=220;                 // 終点で出す「チカッ」(アスタリスク)の長さ(ms)
  let T=0, last=null, flashedCyc=-1, flashT=-1, glintedCyc=-1;
  const glint=()=>{
    if(!faces.length) return;
    const f=faces[Math.floor(Math.random()*faces.length)]; // ランダムに1面
    f.classList.remove('kira'); f.getBoundingClientRect(); f.classList.add('kira'); // reflowで再生し直す
  };
  const placeDot=(r,dist,t)=>{ // dist=距離, t=0(尾)〜1(頭)
    const [x,y]=pointAt(dist);
    const sz=Math.round(TAIL_SZ+(HEAD_SZ-TAIL_SZ)*t); // 頭ほど大きい(整数=ドット絵感)
    r.setAttribute('x',Math.round(x-sz/2));
    r.setAttribute('y',Math.round(y-sz/2));
    r.setAttribute('width',sz);
    r.setAttribute('height',sz);
    // 尾は薄くしない: 全ドット同じ濃さの白いソリッド(濃さはサイズ・間隔だけで表現)
  };
  const [endX,endY]=pointAt(total); // 終点(SR)の座標。チカッはここで出す
  function frame(ts){
    if(last===null)last=ts; T+=ts-last; last=ts;
    const cyc=Math.floor(T/CYCLE), ph=T%CYCLE;
    if(ph<SWEEP){ // 線が走っている間: 尾を描く
      let head;
      if(ph<T_SLOW) head=SLOW_FRAC*total*(ph/T_SLOW);                          // ゆっくり
      else          head=total*(SLOW_FRAC+(1-SLOW_FRAC)*((ph-T_SLOW)/T_FAST)); // はやい
      const tail=Math.max(0, head-TRAIL_LEN); // 尾の末端(最初は0=点、頭が進むと一定長まで伸びる)
      for(let i=0;i<N;i++){
        const t=N>1?i/(N-1):1;                // 0=尾, 1=頭
        placeDot(dots[i], tail+(head-tail)*t, t);
      }
      trailG.style.opacity=(ph<60?ph/60:1).toFixed(3); // すっと現れる
    }else{ // 終点に達した: 尾は消し、その瞬間にチカッ(アスタリスク)を開始
      trailG.style.opacity='0';
      if(flashedCyc!==cyc){ flashT=T; flashedCyc=cyc; }
    }
    // 終点のチカッ(縦長アスタリスク): 終点到達から FLASH ms だけ表示
    let hf=0;
    if(flashT>=0){ const e=T-flashT; if(e>=0 && e<FLASH) hf=1-e/FLASH; } // 瞬時に立ち上がり減衰
    if(hf>0){
      flashG.setAttribute('transform',`translate(${endX.toFixed(1)},${endY.toFixed(1)}) scale(${(0.7+0.5*hf).toFixed(2)})`);
      flashG.style.opacity=hf.toFixed(3);
    }else{
      flashG.style.opacity='0';
    }
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
})();

// ===== 部品スナップ共有定義(ドラッグ／回路の両方で使用) =====
const BB_GRID=24;
const BB_PIN={
  // chip=上下4ピンのみ穴基準(左右は飾り) / battery=±端子 / motor=2リード
  chip:[[0.2925,0.003],[0.687,0.003],[0.687,0.979],[0.2925,0.979]],
  battery:[[0.4805,0.005],[0.4805,0.984]],
  motor:[[0.206,0.9785],[0.769,0.9785]],
};
const BB_SNAPOFF={ chip:[0,12], motor:[0,12] };   // 12=穴上(12+24n) / 0=穴間(24n) / [x,y]=軸別
const BB_NUDGE={ motor:[1,2] };                    // スナップ後の見た目微調整[x,y]px
const bbSnapP=(v,part,ax)=>{ const o=BB_SNAPOFF[part]; const off=Array.isArray(o)?o[ax]:(o!=null?o:12);
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

// ---- 部品をドラッグ→穴にスナップ→配置をCookie保存 ----
(function(){
  const stage=document.querySelector('.stage'); if(!stage) return;
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
  const ticketBtn=document.querySelector('.button-icon.ticket');
  const proposalBtn=document.querySelector('.button-icon.proposal');
  if(!parts.length) return;
  const SW=54, SH=54;
  const connectSnd=()=>{ try{ const c=window.audioCtx&&window.audioCtx(); if(!c) return;
    const t=c.currentTime;
    const o=c.createOscillator(),g=c.createGain(); o.type='triangle';
    o.frequency.setValueAtTime(660,t); o.frequency.exponentialRampToValueAtTime(1320,t+0.12);
    g.gain.setValueAtTime(0.0001,t); g.gain.exponentialRampToValueAtTime(0.2,t+0.02);
    g.gain.exponentialRampToValueAtTime(0.0001,t+0.2);
    o.connect(g); g.connect(c.destination); o.start(t); o.stop(t+0.22);
  }catch(e){} };
  const body=document.body;
  // 各ソケット: 所定の部品(part)が所定の位置(place)に挿さる演出ON。
  const SOCKETS=[
    // チップ → ロゴ右(Kaigi の右隣・縦中央) → PicoRubyKaigi がLチカ。スロットは部品サイズに合わせる
    logo  && { part:'chip',    anchor:logo,  w:56, h:56,
               place:(a,sr)=>({sx:a.right-sr.left+16, sy:a.top-sr.top+(a.height-56)/2}),
               apply:on=>body.classList.toggle('fx-lchika-off', !on) },
    // バッテリー → 下の電源レール(赤+/青-)をまたぐ → ダークモード(暗闇でボードが光る)
    {            part:'battery', anchor:stage, w:27, h:46,
               place:(a,sr)=>{ // 下レール・参加登録とプロポーザルの間
                 let cx=a.width-150;
                 if(ticketBtn&&proposalBtn){ const tk=ticketBtn.getBoundingClientRect(), pr=proposalBtn.getBoundingClientRect();
                   cx=(tk.right+pr.left)/2-sr.left; }
                 return {sx:cx-27/2, sy:a.height-69}; },
               apply:on=>body.classList.toggle('dark', on) },
    // モーター → 内側フィールド → 動力でビルダーが動き出しキューブを組み立て
    scene && { part:'motor',   anchor:scene, w:44, h:57,
               place:(a,sr)=>({sx:a.right-sr.left-72, sy:a.bottom-sr.top-78}), // ルビーの右下に寄せる
               apply:on=>body.classList.toggle('fx-decor-off', !on) },
  ].filter(Boolean);
  SOCKETS.forEach(s=>{ s.el=document.createElement('div'); s.el.className='circuit-slot'; stage.appendChild(s.el); s.was=false; s.wasTouch=false; s.apply(false); });
  function frame(){
    const sr=stage.getBoundingClientRect();
    SOCKETS.forEach(s=>{
      const a=s.anchor.getBoundingClientRect();
      const p0=s.place(a,sr); const W=s.w, H=s.h;
      // ソケット枠を「部品が実際に収まる格子位置」に合わせる
      const [sx,sy]=bbSnapPos(s.part, p0.sx, p0.sy, W, H, sr.height);
      s.el.style.left=sx+'px'; s.el.style.top=sy+'px'; s.el.style.width=W+'px'; s.el.style.height=H+'px';
      const ccx=sx+W/2, ccy=sy+H/2; // ソケット中心
      let inSlot=false, hit=null, touching=false;
      parts.forEach(p=>{ if(p.dataset.part!==s.part) return;            // そのソケット専用の部品だけ
        const r=p.getBoundingClientRect();
        const cx=r.left-sr.left+r.width/2, cy=r.top-sr.top+r.height/2;
        const dx=Math.abs(cx-ccx), dy=Math.abs(cy-ccy);
        if(p.classList.contains('dragging')){ if(dx<=22 && dy<=22) touching=true; } // ドラッグ中にソケットへ触れた(早め)
        else if(dx<=8 && dy<=8){ inSlot=true; hit=p; }                              // 離して ぴったり→モード
      });
      s.apply(inSlot);
      s.el.classList.toggle('filled', inSlot);  // 挿さったら光を消す
      s.el.classList.toggle('hint', !inSlot);
      parts.forEach(p=>{ if(p.dataset.part===s.part) p.classList.toggle('lit-src', inSlot && p===hit); });
      if(touching && !s.wasTouch) connectSnd();          // ソケットに触れた瞬間に通電音
      s.wasTouch=touching;
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
