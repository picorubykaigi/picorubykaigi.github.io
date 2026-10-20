// 属性シール。<div class="sticker" data-sticker="名前"> に、cutpaths.js(cutpath.rb が生成)のカットパスを白い台にして絵を重ねた inline SVG を描く。
// 白い台の輪郭がそのまま切り抜き線。線は印刷しないので描かない。
function renderSticker(element) {
  const cut = CUTPATHS[element.dataset.sticker];
  const image = cut.image;
  const rendering = cut.pixelated ? 'pixelated' : 'auto';
  element.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" width="${cut.w}mm" height="${cut.h}mm" viewBox="0 0 ${cut.w} ${cut.h}">` +
    `<path d="${cut.d}" fill="#fff"/>` +
    `<image href="${cut.src}" x="${image.x}" y="${image.y}" width="${image.w}" height="${image.h}" preserveAspectRatio="none" style="image-rendering: ${rendering};"/>` +
    '</svg>';
}

document.querySelectorAll('.sticker[data-sticker]').forEach(renderSticker);
