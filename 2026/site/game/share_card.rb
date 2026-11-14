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
