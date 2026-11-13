class ShareCard
  EMOJI = ['⬛', '⬜', '🟥', '⬜', '🟨', '🟩', '🟪', '🟧', '🟦']

  def self.text(score, title, core, slow = false)
    lines = []
    lines << '🕹️ GC PANIC - PicoRubyKaigi 2026 Assemble'
    lines << "#{score} bytes 解放・FREE #{core.free_pct}%#{slow ? '・🐢ゆっくり' : ''}"
    lines << case (score + core.ticks) % 3
             when 0 then "#{title}を拾いました"
             when 1 then "#{title}が割り当てられました"
             else "#{title}だけは回収されずに残りました"
             end
    lines.concat(grid(core))
    lines << '#picorubykaigi #picorubykaigi_gc_panic'
    lines.join("\n")
  end

  # 5x5にダウンサンプルした死亡現場。Xは絵文字1個を2文字と数えるので、
  # 10x10の生盤面(重み200)では280の枠に収まらない。塗るのは
  # 「ブロックの過半数が埋まっているとき」だけ・色は最頻色
  # 絵の密度が実際のFREE%と一致するように。箒の赤だけは常に生き残る。
  def self.grid(core)
    f = core.frame
    cols = core.cols
    rws = core.rows
    sx = (cols + 4) / 5
    sy = (rws + 4) / 5
    rows = []
    y = 0
    while y < rws
      line = ''
      x = 0
      while x < cols
        has_p = false
        scanned = 0
        occupied = 0
        counts = {}
        yy = y
        while yy < y + sy && yy < rws
          xx = x
          while xx < x + sx && xx < cols
            c = f[yy][xx]
            scanned += 1
            if c == 2
              has_p = true
            elsif c > 0
              occupied += 1
              counts[c] = (counts[c] || 0) + 1
            end
            xx += 1
          end
          yy += 1
        end
        # ブロックはセルの半分以上が使用中のときだけ、最頻色で塗る。
        code = 0
        if has_p
          code = 2
        elsif occupied * 2 >= scanned
          best_n = 0
          counts.each do |cc, n|
            if n > best_n || (n == best_n && cc > code)
              code = cc
              best_n = n
            end
          end
        end
        line << (EMOJI[code] || '⬛')
        x += sx
      end
      rows << line
      y += sy
    end
    rows
  end
end
