# GC PANIC: プレイヤーは PicoRuby のガベージコレクタ。舞台は小さなヒープ一枚。
# ルールは3つだけ: グレーを掃く、生きているオブジェクトに触れない、
# ヒープは埋まっていく一方。それ以外はすべて創発:
#   - オブジェクトは 1/2/4/8 マス (24/56/96/192 bytes) で、Estalloc の TLSF プール
#     と同じく「連続した」空きマスを要求する。長寿命オブジェクトが散らばると、
#     ヒープが満杯になる前に断片化がアロケーションを殺す——
#     だから OOM の死因は「満杯」と「断片化」の2種類ある
#   - 序盤のオブジェクトは短命なブート時テンポラリ(学習中の安定した獲物)。
#     後半は参照が長く保持されるので、盤面は勝手に混み、通路は勝手に狭まる
class Sweeper
  SHAPES = [
    [[0, 0]],
    [[0, 0], [1, 0]],
    [[0, 0], [0, 1]],
    [[0, 0], [1, 0], [0, 1], [1, 1]],
    [[0, 0], [1, 0], [2, 0], [3, 0], [0, 1], [1, 1], [2, 1], [3, 1]],
    [[0, 0], [0, 1], [0, 2], [0, 3], [1, 0], [1, 1], [1, 2], [1, 3]],
  ]

  attr_reader :phase, :score, :level, :cols, :rows, :chain, :death, :last_freed, :last_tries,
              :gc_starts, :max_chain, :ticks, :barrier_saves

  def initialize(cols = 12, rows = 12)
    @cols = cols
    @rows = rows
    @seed = 60613
    reset
  end

  def reset
    @grid = Array.new(@rows) { Array.new(@cols, nil) }
    @objs = {}
    @next_id = 0
    @px = @cols / 2
    @py = @rows / 2
    @dir = [1, 0]
    @dir_queue = []
    @tick = 0
    @score = 0
    @chain = 0
    @empty_run = 0
    @level = 1
    @death = nil
    @last_freed = 0
    @gc_cd = 0
    @last_tries = 0
    @barrier_cd = 0
    @stun = 0
    @alloc_cursor = nil
    @gc_starts = 0
    @max_chain = 0
    @barrier_saves = 0
    @stw = 0
    @since_mark = 0
    @pending = nil
    @phase = :play
    # 言葉ではなく遊びで教えるチュートリアル: ほぼ空のヒープで開始する。
    # 進行方向にゴミを3粒(触れる=回収)、少し外れに2粒(最初の寄り道への誘い)、
    # そして短命オブジェクトを1体、目の前で死なせて
    # ライフサイクル(色つき→黄→グレー)を見せる。
    3.times do |i|
      x = (@px + 2 + i * 2) % @cols
      next if @grid[@py][x]
      id = @next_id += 1
      @grid[@py][x] = id
      @objs[id] = [:garbage, 90, 24, 0, [[x, @py]]]
    end
    dx = (@px + 3) % @cols
    dy = (@py - 3) % @rows
    unless @grid[dy][dx]
      id = @next_id += 1
      @grid[dy][dx] = id
      @objs[id] = [:live, 18, 24, 18, [[dx, dy]]]
    end
    [[(@px - 3) % @cols, (@py + 2) % @rows], [(@px + 5) % @cols, (@py + 4) % @rows],
     [(@px - 4) % @cols, (@py - 2) % @rows], [(@px + 2) % @cols, (@py + 5) % @rows]].each do |c|
      next if @grid[c[1]][c[0]]
      id = @next_id += 1
      @grid[c[1]][c[0]] = id
      @objs[id] = [:garbage, 90, 24, 0, [c]]
    end
    d2x = (@px - 5) % @cols
    d2y = (@py + 3) % @rows
    unless @grid[d2y][d2x]
      id = @next_id += 1
      @grid[d2y][d2x] = id
      @objs[id] = [:live, 32, 24, 32, [[d2x, d2y]]]
    end
    allocate
  end

  def interval
    ms = 165 - @level * 6
    ms < 130 ? 130 : ms
  end

  def barrier_down?
    @barrier_cd > 0
  end

  def gc_ready?
    @gc_cd <= 0
  end

  def ticks
    @tick
  end

  def player_cell
    [@px, @py]
  end

  # いまの向きのまま2歩以内にトーラスの端を越えるなら着地マスを、
  # 越えないなら nil を返す——ビューが「どこに出てくるか」を予告するため
  def wrap_landing
    d = @dir_queue.first || @dir
    x = @px
    y = @py
    2.times do
      nx = x + d[0]
      ny = y + d[1]
      wx = nx % @cols
      wy = ny % @rows
      return [wx, wy] if wx != nx || wy != ny
      x = wx
      y = wy
    end
    nil
  end

  # 次のオブジェクトが実体化するマス(予告用)
  def pending_cells
    @pending ? @pending[2] : nil
  end

  def garbage_count
    n = 0
    @objs.each { |id, o| n += 1 if o[0] == :garbage }
    n
  end

  # シェルの `free` が見せるもの: 残りヒープ。減っていく一方
  def free_pct
    used = 0
    @rows.times { |y| @cols.times { |x| used += 1 if @grid[y][x] } }
    100 - (used * 100) / (@cols * @rows)
  end

  # GC.start: 全ゴミを一括回収するが手抜き(バイト数は半分)で、
  # そのあとクールダウンに入る。
  def full_gc
    return :none unless @phase == :play
    return :cooldown if @gc_cd > 0
    freed = 0
    ids = []
    @objs.each { |id, o| ids << id if o[0] == :garbage }
    ids.each { |id| freed += free_obj(id) }
    return :none if freed == 0
    @last_freed = freed / 2
    @score += @last_freed
    @chain = 0
    @gc_cd = 60
    @gc_starts += 1
    # フルGCの間、世界は本当に止まる
    @stw = 5
    :fullgc
  end

  # 深さ2の入力キュー: 鋭いS字ターンを先行入力できる(「上、そして左」)。
  def turn(dx, dy)
    return nil unless @phase == :play
    return nil if dx == 0 && dy == 0
    last = @dir_queue.last || @dir
    return nil if last[0] == dx && last[1] == dy
    @dir_queue << [dx, dy]
    @dir_queue.shift while @dir_queue.size > 2
    @seed = (@seed ^ (@px * 31 + @py * 7 + @tick * 13)) & 0x7fffffff
    :turned
  end

  # 1心拍: 箒が1マス進み、そのあとプログラムが1tickぶん走る
  # (参照が切れ、ゴミが朽ち、アロケータが次のオブジェクトを置く)。
  # 戻り値は :frozen / :moved / :sweep / :barrier / :over。
  def step
    return nil unless @phase == :play
    if @stw > 0
      @stw -= 1
      return :frozen
    end
    @tick += 1
    @level = 1 + @tick / 90
    @barrier_cd -= 1 if @barrier_cd > 0
    @gc_cd -= 1 if @gc_cd > 0
    @last_tries = 0
    result = advance_sweeper
    return :over if result == :over
    age_objects
    force_mark_if_dry
    return :over if @tick % alloc_every == 0 && !program_allocates
    result
  end

  # セルコード: 1=ゴミ 2=箒 4=瀕死 5-8=生存色。
  # 生存色は燃えていく導火線: 青(新しい)→紫(半分)→オレンジ(終盤)
  # →黄点滅→グレー(ゴミ)。最初の3段階は各オブジェクト自身の
  # 「寿命の残り割合」を読むので、短命テンポラリも全色を駆け抜け、
  # 盤面は開始数秒から色とりどりになる。黄色の警報だけは絶対時間
  # (残り8tick未満)なので、「黄色=あと数秒」の意味は常に不変。
  def frame
    f = Array.new(@rows) { Array.new(@cols, 0) }
    @objs.each do |id, o|
      code = case o[0]
             when :garbage then o[1] < 12 ? 3 : 1
             else
               t = o[1]
               if t < 8
                 4
               else
                 r = t * 100 / o[3]
                 r < 30 ? 7 : (r < 65 ? 6 : 8)
               end
             end
      o[4].each { |c| f[c[1]][c[0]] = code }
    end
    f[@py][@px] = 2
    f
  end

  private

  # いまの向きに1マス進み(スタン中は1拍休み)、着地先を解決する
  def advance_sweeper
    if @stun > 0
      # バリアに救われた直後のひと休み: 世界は動き続けるが、
      # 操舵を再開する前にひと呼吸おける
      @stun -= 1
      return touch(nil, 0, 0)
    end
    queued = @dir_queue.shift
    @dir = queued if queued
    prev_x = @px
    prev_y = @py
    @px = (@px + @dir[0]) % @cols
    @py = (@py + @dir[1]) % @rows
    touch(@grid[@py][@px], prev_x, prev_y)
  end

  def touch(id, prev_x, prev_y)
    unless id
      @empty_run += 1
      @chain = 0 if @empty_run >= 4
      return :moved
    end
    o = @objs[id]
    if o[0] == :garbage
      collect(id)
    elsif @barrier_cd > 0
      # バリアはまだ充電中: 今度の不正解放は素通りし、
      # プログラムはダングリング参照で死ぬ
      @death = :segv
      @phase = :over
      :over
    else
      barrier_bounce(prev_x, prev_y)
    end
  end

  def collect(id)
    bytes = free_obj(id)
    @chain += 1
    @max_chain = @chain if @chain > @max_chain
    # 連鎖した解放はひとつの大きなフリーブロックに合体する。合体1回につき
    # USED_BLOCK ヘッダちょうど1個ぶん = 4 bytes が戻る (estalloc.c)
    bytes += 4 if @chain >= 2
    # 連鎖数がそのままスコア倍率(×8でキャップ)
    mult = @chain > 8 ? 8 : @chain
    bytes *= mult if mult > 1
    @score += bytes
    @last_freed = bytes
    @empty_run = 0
    :sweep
  end

  # ライトバリアが危険なタッチを捕まえる: オブジェクトは再マークされ、
  # 箒は弾き返され、バリアは再充電が必要になる
  def barrier_bounce(prev_x, prev_y)
    @barrier_saves += 1
    @px = prev_x
    @py = prev_y
    @dir = [-@dir[0], -@dir[1]]
    @dir_queue = []
    @barrier_cd = 40
    @stun = 5
    @chain = 0
    :barrier
  end

  # プログラムが走ると参照は切れていく: 生存オブジェクトはゴミになる。
  # ゴミにも期限がある: 放置したぶんは遅い背景GCが回収してしまう(得点なし)。
  # 消える前には点滅して知らせる。
  def age_objects
    expired = []
    @since_mark += 1
    @objs.each do |oid, o|
      if o[0] == :live
        o[1] -= 1
        if o[1] <= 0
          o[0] = :garbage
          # 背景GCの回収はゆっくりめ(約11〜15秒)
          o[1] = 70 + rand_n(25)
          @since_mark = 0
        end
      else
        o[1] -= 1
        expired << oid if o[1] <= 0
      end
    end
    expired.each { |oid| free_obj(oid) }
  end

  # リズムの床: 約2秒なにもマークされず盤上のゴミも枯れかけなら、
  # プログラムはいちばん古い参照をいますぐ手放す
  # (mruby PR #6938 のスケジューラ駆動GCが回収を促すのと同じ理屈)。
  # 世代交代・盤面サイズ・FULL GC のタイミングがどう転んでも、
  # 「掃くものがない空白」は生まれない。
  def force_mark_if_dry
    return unless @since_mark > 12 && garbage_count < 3
    victim = nil
    @objs.each do |_oid, o|
      victim = o if o[0] == :live && (victim.nil? || o[1] < victim[1])
    end
    victim[1] = 3 if victim && victim[1] > 3
  end

  # false = メモリ不足: 死因は「本当に満杯だった」か
  # 「断片化で要求サイズが入らなかっただけ」かで判定する
  def program_allocates
    return true if allocate
    used = 0
    @rows.times { |y| @cols.times { |x| used += 1 if @grid[y][x] } }
    @death = used >= (@cols * @rows * 85) / 100 ? :oom_full : :oom_frag
    @phase = :over
    false
  end

  # ゆるやかに、ただし間延びなく立ち上げる: 開始数秒から獲物は流れてくる
  def alloc_every
    return 8 if @tick < 150
    # 以前より1tick速い: アロケーションの40%が短命テンポラリになったので、
    # これがないとヒープの混み方が目に見えて遅くなる
    e = 6 - @level / 2
    e < 3 ? 3 : e
  end

  # アロケーションは1個先行のパイプライン: 「次の」オブジェクトの場所は
  # ひとつ前のアロケーション時に決まるので、ビューが実体化位置を予告できる。
  # 配置自体は失敗しない(予告済みマスは空きのまま——グリッドを書くのは
  # ここだけ)。場所探しの失敗こそが OOM として現れる。
  def allocate
    placed = false
    if @pending
      ttl, bytes, cells = @pending
      id = @next_id += 1
      cells.each { |c| @grid[c[1]][c[0]] = id }
      @objs[id] = [:live, ttl, bytes, ttl, cells]
      @alloc_cursor = [cells[0][0], cells[0][1]]
      @pending = nil
      placed = true
    end
    @pending = find_spot
    placed || !@pending.nil?
  end

  # 次のオブジェクトの [ttl, bytes, cells] を選ぶ。複数マスのオブジェクトは
  # 連続した空きマスが必要: 合計の空きがどれだけあっても、
  # 断片化したヒープは大きなアロケーションを拒む。
  def find_spot
    r = rand_n(100)
    shape = if r < 55
              SHAPES[0]
            elsif r < 70
              SHAPES[1]
            elsif r < 85
              SHAPES[2]
            elsif r < 95
              SHAPES[3]
            else
              # レアな大物: 断片化したヒープが最初に拒否する連続要求
              r % 2 == 0 ? SHAPES[4] : SHAPES[5]
            end
    # 32bit PicoRuby の実寸: 素のオブジェクトは RVALUE 1個 = 24 bytes
    # (mruby の gc.c が 32bit では 24 にパディングしている)。バッファ持ち
    # (String など)は最小の Estalloc ブロックが足されて 24 + 32 = 56。
    # 大物(要素16個の Array)はデータ 64B + ヘッダ 4B を 8 バイト整列して
    # 24 + 72 = 96。
    bytes = shape.size == 1 ? 24 : (shape.size == 2 ? 56 : (shape.size == 4 ? 96 : 192))
    # 世代仮説: ほとんどのオブジェクトは若くして死ぬ——ブート中だけでなく
    # 「常に」。テンポラリ率は100%から定常の40%へ徐々に下がるが、
    # このフェードは長寿命組のTTL遅延(約68tick)より長くなければならない:
    # tick T に置かれた長寿命組が死に始めるのは T+30〜T+100 なので、
    # フェードが速すぎると40〜50秒あたりに死亡レートの穴が開く
    # (実測: そこで sweep/tick が3分の1落ちた)。
    p = 100 - (@tick - 150) / 4
    p = 40 if p < 40
    if rand_n(100) < p
      ttl = 10 + rand_n(25)
    else
      ttl = 30 + rand_n(70) + @level * 6
    end
    # アロケーションの局所性: 連続する割り当ては近いアドレスに落ちるので、
    # ヒープは塊で埋まっていく(あいだに通路が残る)。
    # 地雷が均一にばらまかれた霧にはならない
    @alloc_cursor = [rand_n(@cols), rand_n(@rows)] unless @alloc_cursor
    40.times do |try_i|
      @last_tries = try_i + 1
      if try_i < 24
        x = (@alloc_cursor[0] + rand_n(7) - 3) % @cols
        y = (@alloc_cursor[1] + rand_n(7) - 3) % @rows
      else
        x = rand_n(@cols)
        y = rand_n(@rows)
      end
      ok = true
      shape.each do |d|
        cx = x + d[0]
        cy = y + d[1]
        if cx >= @cols || cy >= @rows || @grid[cy][cx] || torus_dist(cx, cy) < 3
          ok = false
          break
        end
      end
      next unless ok
      cells = shape.map { |d| [x + d[0], y + d[1]] }
      return [ttl, bytes, cells]
    end
    nil
  end

  # 箒までのラップ考慮距離(盤面はトーラス)
  def torus_dist(x, y)
    dx = (x - @px).abs
    dx = @cols - dx if dx > @cols / 2
    dy = (y - @py).abs
    dy = @rows - dy if dy > @rows / 2
    dx + dy
  end

  def free_obj(id)
    o = @objs[id]
    o[4].each { |c| @grid[c[1]][c[0]] = nil }
    @objs.delete(id)
    o[2]
  end

  def rand_n(n)
    @seed = (@seed * 1103515245 + 12345) & 0x7fffffff
    (@seed >> 16) % n
  end
end
