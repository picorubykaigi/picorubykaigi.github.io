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
