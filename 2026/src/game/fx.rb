require 'js'

class Fx
  def initialize
    @board = JS.document.querySelector('.board')
    @score_el = JS.document.querySelector('.hud-value')
    @pop_alt = false
  end

  def sfx
    fx = JS.global[:gameSfx]
    yield fx if fx
  end

  # 回収の瞬間: HUDのスコア数字がドンと弾み、いま解放したバイト数が
  # 掃いたその場所からふわりと浮かぶ
  def sweep(core)
    if @score_el
      @pop_alt = !@pop_alt
      @score_el[:className] = @pop_alt ? 'hud-value pop' : 'hud-value pop2'
    end
    float_score(core)
    micro_spark(core)
  end

  # 常時発動のいちばん下のジュース層: sweepごとに金の火花が2粒だけ
  # (紙吹雪は連鎖の節目専用にとっておく)
  SPARK = ['#ffe08a', '#fff6d8']

  def micro_spark(core)
    m = JS.document.querySelector('.matrix')
    return unless @board && m
    br = @board.getBoundingClientRect
    mr = m.getBoundingClientRect
    pc = core.player_cell
    x = mr[:left].to_f - br[:left].to_f + (pc[0] + 0.5) * (mr[:width].to_f / core.cols)
    y = mr[:top].to_f - br[:top].to_f + (pc[1] + 0.5) * (mr[:height].to_f / core.rows)
    2.times do |i|
      el = JS.document.createElement('div')
      el[:className] = 'spark-bit'
      el[:style][:left] = "#{x.to_i}px"
      el[:style][:top] = "#{y.to_i}px"
      el[:style][:background] = SPARK[i]
      d = SPREAD[(core.ticks * 3 + i * 5) % 8]
      dist = 14 + ((core.ticks + i) % 3) * 5
      el[:style].setProperty('--cx', "#{d[0] * dist}px")
      el[:style].setProperty('--cy', "#{d[1] * dist}px")
      @board.appendChild(el)
      JS.global.setTimeout(420) { el.remove }
    end
  end

  def float_score(core)
    m = JS.document.querySelector('.matrix')
    return unless @board && m
    bytes = core.last_freed
    chain = core.chain
    br = @board.getBoundingClientRect
    mr = m.getBoundingClientRect
    pc = core.player_cell
    x = mr[:left].to_f - br[:left].to_f + (pc[0] + 0.5) * (mr[:width].to_f / core.cols)
    y = mr[:top].to_f - br[:top].to_f + pc[1] * (mr[:height].to_f / core.rows)
    el = JS.document.createElement('div')
    # スコアの隣にキャンディみたいな連鎖数ピルが出る
    el[:className] = 'float-score'
    if chain >= 2
      bel = JS.document.createElement('span')
      bel[:textContent] = "+#{bytes}"
      pill = JS.document.createElement('span')
      pill[:className] = chain >= 5 ? 'fs-pill hot' : 'fs-pill'
      pill[:textContent] = "×#{chain}"
      # ピルは連鎖に応じて育つ
      size = 12 + chain
      size = 20 if size > 20
      pill[:style][:fontSize] = "#{size}px"
      el.appendChild(bel)
      el.appendChild(pill)
    else
      el[:textContent] = "+#{bytes}"
    end
    el[:style][:left] = "#{x.to_i}px"
    el[:style][:top] = "#{y.to_i}px"
    @board.appendChild(el)
    JS.global.setTimeout(chain >= 2 ? 850 : 700) { el.remove }
  end

  # 連鎖の節目のパーティ弾け: LED色の紙吹雪が箒のマスから飛び散る
  CONFETTI = ['#fb5479', '#56f096', '#ffc12e', '#58aef5', '#b784f5', '#ff8a3d', '#fb5479', '#56f096']
  SPREAD = [[1, 0], [1, -1], [0, -1], [-1, -1], [-1, 0], [-1, 1], [0, 1], [1, 1]]

  def confetti(core)
    m = JS.document.querySelector('.matrix')
    return unless @board && m
    br = @board.getBoundingClientRect
    mr = m.getBoundingClientRect
    pc = core.player_cell
    x = mr[:left].to_f - br[:left].to_f + (pc[0] + 0.5) * (mr[:width].to_f / core.cols)
    y = mr[:top].to_f - br[:top].to_f + (pc[1] + 0.5) * (mr[:height].to_f / core.rows)
    8.times do |i|
      el = JS.document.createElement('div')
      el[:className] = 'confetti-bit'
      el[:style][:left] = "#{x.to_i}px"
      el[:style][:top] = "#{y.to_i}px"
      el[:style][:background] = CONFETTI[i]
      d = SPREAD[i]
      dist = 30 + (i % 3) * 12
      el[:style].setProperty('--cx', "#{d[0] * dist}px")
      el[:style].setProperty('--cy', "#{d[1] * dist}px")
      @board.appendChild(el)
      JS.global.setTimeout(650) { el.remove }
    end
  end

  # Stop The World: 白く光ったあと、凍結のあいだ盤面全体から色が抜ける
  def stw_flash
    return unless @board
    @board[:className] = 'board stw'
    JS.global.setTimeout(780) { @board[:className] = 'board' }
  end

  # 合体の節目にヒープ全体がドンと脈打つ
  def pulse
    return unless @board
    @board[:className] = 'board pulse'
    JS.global.setTimeout(280) { @board[:className] = 'board' }
  end

  # SEGVは死亡演出で物語る: 不正解放(crack)、まだ走っている
  # プログラムの一拍(glitch)、そしてクラッシュ(shake)
  def shake(death)
    return unless @board
    if death == :segv
      sfx { |f| f.crack }
      @board[:className] = 'board glitch'
      JS.global.setTimeout(350) do
        @board[:className] = 'board shake-big'
        JS.global.setTimeout(420) { @board[:className] = 'board' }
      end
    else
      @board[:className] = 'board shake-big'
      JS.global.setTimeout(420) { @board[:className] = 'board' }
    end
  end
end
