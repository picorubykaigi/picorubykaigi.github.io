// ゲームへのQRコード生成(ルビー風): データ=LEDドット / ファインダーもドット /
// 中央=「GAME」のピクセル文字。地色はカード裏の地(#10131c)と同色の反転QRで、カードに溶け込ませる。
// URLを変えたら GAME_URL を書き換えて再生成:
//   node gen-qr.mjs > qr-ruby-dark-game.svg
import { createRequire } from 'module';
const qrcode = createRequire(import.meta.url)('qrcode');

const GAME_URL = 'https://picorubykaigi.org/game';

// 誤り訂正H(30%復元): 中央を「GAME」で潰しても読めるように
const qr = qrcode.create(GAME_URL, { errorCorrectionLevel: 'H' });
const n = qr.modules.size;            // モジュール数(1辺)
const data = qr.modules.data;
const QUIET = 4;                      // 静穏域(スペック通り4モジュール)
const size = n + QUIET * 2;

const at = (x, y) => data[y * n + x] === 1;

// ファインダーパターン(三隅の目)の範囲。下で別途ドットで描くのでデータからは除外
const inFinder = (x, y) =>
  (x < 7 && y < 7) || (x >= n - 7 && y < 7) || (x < 7 && y >= n - 7);

const cx = n / 2, cy = n / 2;
// 中央の「GAME」: 3x5ピクセルフォント(Mだけ5幅)。1文字1色でパーティカラー
const F = {
  G: ['111', '100', '101', '101', '111'],
  A: ['111', '101', '111', '101', '101'],
  M: ['10001', '11011', '10101', '10001', '10001'],
  E: ['111', '100', '111', '100', '111'],
};
const C = ['#8ee8ac', '#ffd166', '#8ad9ff', '#ff9fb4'];   // 緑/黄/シアン/ピンク(文字ごとに巡回)
const glyphs = [...'GAME'].map((ch, i) => ({ rows: F[ch], color: C[i % C.length] }));
const GAME_W = glyphs.reduce((w, g) => w + g.rows[0].length + 1, -1);   // 文字幅の合計
const GAME_H = 5;

// アイコン領域(GAME)。文字が地のドットに溶けないよう暗いフチを .6 取る
// (.8以上はグレースケール読取が落ちる=ECC予算超え)
const iconBox = { x0: cx - GAME_W / 2 - .6, x1: cx + GAME_W / 2 + .6, y0: cy - GAME_H / 2 - .6, y1: cy + GAME_H / 2 + .6 };
const inIcon = (x, y) => x + .5 > iconBox.x0 && x + .5 < iconBox.x1 && y + .5 > iconBox.y0 && y + .5 < iconBox.y1;

const BG = '#10131c';
const MODS = ['#8ee8ac', '#ffd166', '#8ad9ff', '#ff9fb4'];   // 緑/黄/シアン/ピンク
// 斜めの縞になるよう塗り分ける(x+y が等しい斜めラインごとに同色。2モジュール幅の帯)
const mod = (x, y) => MODS[Math.floor((x + y) / 2) % MODS.length];

let out = [];
out.push(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${size} ${size}">`);
out.push(`<rect width="${size}" height="${size}" fill="${BG}"/>`);

// データモジュール(角丸ドット。ファインダー・中央アイコンは除外)
for (let y = 0; y < n; y++) {
  for (let x = 0; x < n; x++) {
    if (!at(x, y) || inFinder(x, y) || inIcon(x, y)) continue;
    out.push(`<rect x="${QUIET + x + .04}" y="${QUIET + y + .04}" width=".92" height=".92" rx=".27" fill="${mod(x, y)}"/>`);
  }
}

// ファインダーパターン: データと同じドットで1粒ずつ(正規の7x7リング+3x3中心)
const finder = (fx, fy) => {
  for (let y = 0; y < 7; y++)
    for (let x = 0; x < 7; x++) {
      const ring = x === 0 || x === 6 || y === 0 || y === 6;
      const core = x >= 2 && x <= 4 && y >= 2 && y <= 4;
      if (!ring && !core) continue;
      const gx = fx + x, gy = fy + y;
      out.push(`<rect x="${QUIET + gx + .04}" y="${QUIET + gy + .04}" width=".92" height=".92" rx=".27" fill="${mod(gx, gy)}"/>`);
    }
};
finder(0, 0);
finder(n - 7, 0);
finder(0, n - 7);

// 中央の「GAME」(QRのドットと同じ粒で描く)
let gx = cx - GAME_W / 2;
const gy = cy - GAME_H / 2;
for (const g of glyphs) {
  g.rows.forEach((row, ry) => {
    [...row].forEach((c, rx) => {
      if (c !== '1') return;
      out.push(`<rect x="${(QUIET + gx + rx + .04).toFixed(2)}" y="${(QUIET + gy + ry + .04).toFixed(2)}" width=".92" height=".92" rx=".27" fill="${g.color}"/>`);
    });
  });
  gx += g.rows[0].length + 1;
}

out.push('</svg>');
console.log(out.join('\n'));
console.error(`modules: ${n}x${n}, url: ${GAME_URL}`);
