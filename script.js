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
