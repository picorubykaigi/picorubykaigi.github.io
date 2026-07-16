require 'js'

# MALLOC PANIC: you are PicoRuby's memory allocator on one small heap.
# The mirror image of GC PANIC -- there you swept, here you place.
# Flat Tetris, but the falling is up to you: every request is a tetromino
# (4 cells = 256 bytes) and you decide where on the heap it lives.
#
# The clear rule is memory reuse itself, nothing invented -- and it
# fires ON YOUR DROP, never on a timer, and takes EXACTLY what the drop
# touches:
#   grey (dead) cells are legal ground. Place a piece onto garbage and
#   the allocator reclaims precisely the dead blocks under your piece --
#   what lights up pink under the ghost is what will vanish, nothing
#   more. One drop, one honest bite.
# Time only GROWS the grey -- pieces age into garbage on their own
# schedule, green ones soon, blue ones much later -- but nothing ever
# vanishes except by your hand. Clearing a big grey field takes several
# well-aimed drops, and an I-piece laid across four dead neighbours is
# the jackpot you set up lifetimes ago.
# The rest is emergent:
#   - blocks need CONTIGUOUS legal cells, so there are two OOM causes:
#     "full" and "fragmentation" -- and the live long-livers you placed
#     carelessly are the walls that cause the second. No GC saves you:
#     grey was already usable ground, so when nothing fits, it is truly
#     over
#   - if you dawdle on placing, the allocator falls back to dumb
#     first-fit over truly empty cells only (collecting is your job,
#     not malloc's) -- zero points, and a heap buried in uncollected
#     grey leaves it nowhere to go
class Allocator
  # the seven tetrominoes, spawn orientation (rotation is a player move)
  SHAPES = [
    [[0, 0], [1, 0], [2, 0], [3, 0]],  # I
    [[0, 0], [1, 0], [0, 1], [1, 1]],  # O
    [[0, 0], [1, 0], [2, 0], [1, 1]],  # T
    [[1, 0], [2, 0], [0, 1], [1, 1]],  # S
    [[0, 0], [1, 0], [1, 1], [2, 1]],  # Z
    [[0, 0], [1, 0], [2, 0], [0, 1]],  # L
    [[0, 0], [1, 0], [2, 0], [2, 1]],  # J
  ]
  BYTES = 256
  # below this ttl the object blinks yellow (refs about to drop); at 0 it
  # turns grey garbage and sits there until a drop reuses it
  DYING = 12
  # like Tetris, the points live in the clear, not the drop -- and the
  # curve lives in HOW MANY you clear at once. One dead piece reclaimed
  # is pocket change; a single drop bridging four is the I-piece moment
  # you spent the whole run setting up.
  COMBO_PTS = [0, 64, 256, 576, 1024]
  EXTRA_PTS = 256
  # placing pays a token amount; skill pays through perfect fits & combos
  PLACE_PTS = 64
  attr_reader :phase, :score, :level, :cols, :rows, :chain, :death,
              :req_cells, :req_life, :queue, :patience, :patience_max,
              :max_chain, :last_alloc, :last_bonus, :last_combo,
              :last_salvage, :max_combo

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
    @tick = 0
    @score = 0
    @chain = 0
    @max_chain = 0
    @level = 1
    @death = nil
    @last_alloc = 0
    @last_bonus = 0
    @last_combo = 0
    @last_salvage = 0
    @max_combo = 0
    @gx = @cols / 2
    @gy = @rows / 2
    @phase = :play
    # Tutorial by play, not by words: boot into a heap already mid-flight.
    # Everything on this heap is a tetromino, the seeds included. Green
    # boot temporaries at various ages show the life cycle (green ->
    # yellow -> grey -> still there) before the first request even lands,
    # and one blue long-liver shows the other kind.
    # [shape, x, y, ttl, life]
    [[0, 1, 2, 18, 0], [3, 7, 2, 26, 0], [5, 2, 8, 10, 0], [1, 8, 7, 140, 1]].each do |s|
      cells = SHAPES[s[0]].map { |d| [s[1] + d[0], s[2] + d[1]] }
      ok = true
      cells.each { |c| ok = false if c[0] >= @cols || c[1] >= @rows || @grid[c[1]][c[0]] }
      next unless ok
      id = @next_id += 1
      cells.each { |c| @grid[c[1]][c[0]] = id }
      @objs[id] = [s[3], BYTES, s[4], cells]
    end
    @queue = []
    3.times { @queue << gen_request }
    next_request
  end

  def interval
    140
  end

  def ticks
    @tick
  end

  def ghost_cell
    [@gx, @gy]
  end

  def garbage_count
    n = 0
    @objs.each { |id, o| n += 1 if o[0] <= 0 }
    n
  end

  # What the shell's `free` shows: remaining heap
  def free_pct
    used = 0
    @rows.times { |y| @cols.times { |x| used += 1 if @grid[y][x] } }
    100 - (used * 100) / (@cols * @rows)
  end

  # Ghost steering (keyboard): one cell at a time, clamped to the board
  def move(dx, dy)
    return nil unless @phase == :play
    move_to(@gx + dx, @gy + dy)
  end

  # Ghost steering (pointer): jump straight to the touched cell
  def move_to(x, y)
    return nil unless @phase == :play
    ox = @gx
    oy = @gy
    @gx = x
    @gy = y
    clamp_ghost
    @seed = (@seed ^ (@gx * 31 + @gy * 7 + @tick * 13)) & 0x7fffffff
    @gx == ox && @gy == oy ? nil : :moved
  end

  def rotate
    return nil unless @phase == :play
    @req_cells = rotate_cells(@req_cells)
    clamp_ghost
    :rotated
  end

  # grey is legal ground: dead memory is exactly what an allocator reuses
  def can_place?
    @req_cells.each do |d|
      cx = @gx + d[0]
      cy = @gy + d[1]
      return false if cx >= @cols || cy >= @rows
      id = @grid[cy][cx]
      return false if id && @objs[id][0] > 0
    end
    true
  end

  # The player action. Returns :harvest / :perfect / :placed / :blocked.
  # Afterwards check phase (this drop may have crowded the heap so the
  # NEXT request has nowhere to go: game over).
  def place
    return :blocked unless @phase == :play
    return :blocked unless can_place?
    # THE satisfying beat, on your drop and only on your drop: reclaim
    # exactly the dead pieces under this one -- what glowed pink is
    # what goes, nothing more. The combo count is the whole game:
    # bridging four dead neighbours with one piece is the payoff you
    # built toward since you laid that row of same-lifetime allocations
    combo = harvest_at(@gx, @gy, @req_cells)
    cells = put_object(@gx, @gy, @req_cells)
    @last_alloc = PLACE_PTS
    bonus = 0
    # best-fit reward: plugging a hole exactly your shape leaves no
    # crumbs behind
    if perfect_fit?(cells)
      @chain += 1
      @max_chain = @chain if @chain > @max_chain
      extra = (@chain - 1) * 32
      extra = 96 if extra > 96
      bonus = 64 + extra
    else
      @chain = 0
    end
    @last_bonus = bonus
    @last_combo = combo
    @max_combo = combo if combo > @max_combo
    salvage = combo > 4 ? COMBO_PTS[4] + (combo - 4) * EXTRA_PTS : COMBO_PTS[combo]
    @last_salvage = salvage
    @score += PLACE_PTS + bonus + salvage
    next_request
    return :harvest if combo > 0
    bonus > 0 ? :perfect : :placed
  end

  # Returns :tick / :autoplace / :over.
  def step
    return nil unless @phase == :play
    @tick += 1
    # references drop as the program runs, but the memory stays claimed:
    # dead objects grey out and SIT THERE until a drop reuses them
    @objs.each do |oid, o|
      o[0] -= 1 if o[0] > 0
    end
    @level = 1 + @tick / 70
    r = deadline_tick
    return r if r
    :tick
  end

  # cell codes: 1=garbage 4=dying 5=short-lived 8=long-lived
  #             9/10=ghost 11=ghost(blocked) 12=ghost(harvest!)
  #             13=garbage that THIS drop would reclaim
  def frame
    f = Array.new(@rows) { Array.new(@cols, 0) }
    @objs.each do |id, o|
      code = o[0] <= 0 ? 1 : (o[0] < DYING ? 4 : (o[2] == 1 ? 8 : 5))
      o[3].each { |c| f[c[1]][c[0]] = code }
    end
    if @phase == :play
      g = 11
      if can_place?
        g = @req_life == 1 ? 10 : 9
        # what-you-see-is-what-you-sweep: every garbage object the piece
        # touches lights up pink, cell for cell, before you commit
        touched = {}
        @req_cells.each do |d|
          id = @grid[@gy + d[1]][@gx + d[0]]
          touched[id] = true if id && @objs[id][0] <= 0
        end
        if touched.size > 0
          g = 12
          touched.each do |id, _|
            @objs[id][3].each { |c| f[c[1]][c[0]] = 13 }
          end
        end
      end
      @req_cells.each do |d|
        cx = @gx + d[0]
        cy = @gy + d[1]
        f[cy][cx] = g if cy < @rows && cx < @cols
      end
    end
    f
  end

  private

  # Reclaim exactly the garbage objects under the shape's footprint --
  # whole objects (memory is reused block by block), but ONLY the ones
  # the piece actually touches. What glowed pink is what goes.
  # Returns how many objects went (the combo).
  def harvest_at(x, y, shape)
    touched = {}
    shape.each do |d|
      id = @grid[y + d[1]][x + d[0]]
      touched[id] = true if id && @objs[id][0] <= 0
    end
    n = 0
    touched.each do |id, _|
      free_obj(id)
      n += 1
    end
    n
  end

  # the allocation path with grey as reusable ground: if the request
  # cannot be placed anywhere, no GC can save you (garbage was already
  # usable) -- that is a true OUT OF MEMORY
  def ensure_allocatable
    return if fits_anywhere?
    used = 0
    @rows.times { |y| @cols.times { |x| used += 1 if @grid[y][x] } }
    @death = used >= (@cols * @rows * 85) / 100 ? :oom_full : :oom_frag
    @phase = :over
  end

  # rotate 90 degrees and renormalize to the top-left origin
  def rotate_cells(cells)
    r = cells.map { |d| [d[1], -d[0]] }
    minx = 99
    miny = 99
    r.each do |d|
      minx = d[0] if d[0] < minx
      miny = d[1] if d[1] < miny
    end
    r.map { |d| [d[0] - minx, d[1] - miny] }
  end

  # The malloc deadline advances every tick.
  # Returns :autoplace / :over when it runs out, nil otherwise.
  def deadline_tick
    @patience -= 1
    return nil if @patience > 0
    # the program waited too long on malloc: the allocator falls back to
    # dumb first-fit. Dumb means REALLY dumb -- it cannot reclaim your
    # garbage (only you, the collector, can), so it needs truly empty
    # cells. A heap buried in uncollected grey has none: that is a real
    # leak, and a real OUT OF MEMORY.
    unless autoplace
      used = 0
      @rows.times { |y| @cols.times { |x| used += 1 if @grid[y][x] } }
      @death = used >= (@cols * @rows * 85) / 100 ? :oom_full : :oom_frag
      @phase = :over
      return :over
    end
    return :over if @phase == :over
    :autoplace
  end

  # Ramp: difficulty comes from the BOARD, not the clock. Later requests
  # cling to their references longer and longer, so live walls crowd the
  # heap and every placement becomes a tighter puzzle -- while the
  # deadline stays humane enough to actually think through it
  def gen_request
    si = rand_n(7)
    pl = @tick < 100 ? 15 : 30 + @level * 10
    pl = 92 if pl > 92
    life = rand_n(100) < pl ? 1 : 0
    [si, life]
  end

  # Green lifetimes are TIGHT on purpose: a row of greens laid together
  # greys out together, so the strip you built becomes a plannable
  # harvest window instead of a lottery
  def roll_ttl(life)
    life == 1 ? 100 + rand_n(60) + @level * 16 : 28 + rand_n(8)
  end

  def next_request
    req = @queue.shift
    @queue << gen_request
    @req_cells = SHAPES[req[0]]
    @req_life = req[1]
    # the deadline barely tightens: this is a thinking game, and the
    # squeeze is supposed to come from the crowded heap instead
    pm = @tick < 100 ? 32 : 30 - @level
    pm = 20 if pm < 20
    @patience_max = pm
    @patience = pm
    clamp_ghost
    # the allocation path: fit somewhere (grey included), or die
    ensure_allocatable
  end

  def clamp_ghost
    w = 0
    h = 0
    @req_cells.each do |d|
      w = d[0] if d[0] > w
      h = d[1] if d[1] > h
    end
    @gx = 0 if @gx < 0
    @gy = 0 if @gy < 0
    @gx = @cols - 1 - w if @gx > @cols - 1 - w
    @gy = @rows - 1 - h if @gy > @rows - 1 - h
  end

  def put_object(x, y, shape)
    id = @next_id += 1
    cells = shape.map { |d| [x + d[0], y + d[1]] }
    cells.each { |c| @grid[c[1]][c[0]] = id }
    @objs[id] = [roll_ttl(@req_life), BYTES, @req_life, cells]
    cells
  end

  # a perfect fit: every side of the placed shape touches a wall or
  # another object -- the hole was exactly this shape
  def perfect_fit?(cells)
    cells.each do |c|
      [[1, 0], [-1, 0], [0, 1], [0, -1]].each do |d|
        nx = c[0] + d[0]
        ny = c[1] + d[1]
        next if nx < 0 || ny < 0 || nx >= @cols || ny >= @rows
        return false unless @grid[ny][nx]
      end
    end
    true
  end

  # a legal spot allows empty AND grey cells, same as the player's drop
  def find_fit_for(shape)
    @rows.times do |y|
      @cols.times do |x|
        ok = true
        shape.each do |d|
          cx = x + d[0]
          cy = y + d[1]
          if cx >= @cols || cy >= @rows
            ok = false
            break
          end
          id = @grid[cy][cx]
          if id && @objs[id][0] > 0
            ok = false
            break
          end
        end
        return [x, y] if ok
      end
    end
    nil
  end

  # the player can rotate, so "cannot fit" must mean NO orientation fits
  def fits_anywhere?
    cells = @req_cells
    4.times do
      return true if find_fit_for(cells)
      cells = rotate_cells(cells)
    end
    false
  end

  # first-fit fallback: scan from the top-left, take the first EMPTY
  # opening (trying rotations only if it must). Deliberately dumb -- it
  # cannot touch garbage, because collecting is your job, not malloc's
  def autoplace
    cells = @req_cells
    4.times do
      pos = find_empty_fit_for(cells)
      if pos
        put_object(pos[0], pos[1], cells)
        @chain = 0
        next_request
        return true
      end
      cells = rotate_cells(cells)
    end
    false
  end

  def find_empty_fit_for(shape)
    @rows.times do |y|
      @cols.times do |x|
        ok = true
        shape.each do |d|
          cx = x + d[0]
          cy = y + d[1]
          if cx >= @cols || cy >= @rows || @grid[cy][cx]
            ok = false
            break
          end
        end
        return [x, y] if ok
      end
    end
    nil
  end

  def free_obj(id)
    o = @objs[id]
    o[3].each { |c| @grid[c[1]][c[0]] = nil }
    @objs.delete(id)
    o[1]
  end

  def rand_n(n)
    @seed = (@seed * 1103515245 + 12345) & 0x7fffffff
    (@seed >> 16) % n
  end
end

class App < Funicular::Component
  COLS = 12
  ROWS = 12
  CELL_CLASS = ['cell c0', 'cell c1', 'cell c2', 'cell c3', 'cell c4',
                'cell c5', 'cell c6', 'cell c7', 'cell c8',
                'cell g1', 'cell g2', 'cell g3', 'cell g4', 'cell g5']
  BEST_KEY = 'malloc-panic-best'

  # Score-tier titles: they give the byte count a face worth sharing
  TITLES = [
    [12000, ['アロケータの かみさま', 'メモリの だいまじん']],
    [10000, ['TLSFの けんじゃ', 'すきまの まじゅつし']],
    [8500, ['ぴったり キング', 'しきつめの てつじん']],
    [7000, ['ヒープの せっけいし', 'メモリの まもりびと']],
    [5800, ['ベテラン アロケータ', 'うでっこき おきやさん']],
    [4700, ['すきま はかせ', 'ろじうらの ぬし']],
    [3800, ['げんば かんとく', 'おきば はんちょう']],
    [3000, ['はたらく malloc', 'コツコツ つめるひと']],
    [2200, ['まちの おきやさん', 'ブロック デビュー']],
    [1400, ['みならい malloc', 'つめかた れんしゅうちゅう']],
    [600, ['おきっぱなしや', 'ちらかしずき']],
    [0, ['よちよち ポインタ', 'まよえる ぬるぽ']],
  ]

  # frame code -> emoji for the shareable board picture
  EMOJI = ['⬛', '⬜', '⬛', '⬛', '🟨', '🟩', '🟪', '🟧', '🟦', '⬛', '⬛', '⬛', '⬛', '⬜']

  MESSAGES_TOUCH = {
    'ready' => ['TAP TO START', 'ゴミ(はいいろ)は うえに おいて かいしゅう・いちどに 4こで テトラ！'],
    'play'  => ['', 'ドラッグで おく・ピンクに ひかった ゴミが きえる'],
    'over'  => ['OUT OF MEMORY', 'タップで もういちど'],
  }

  MESSAGES_PC = {
    'ready' => ['PRESS SPACE', 'ゴミ(はいいろ)は うえに おいて かいしゅう・いちどに 4こで テトラ！'],
    'play'  => ['', 'やじるし+スペースで おく・R で かいてん・ピンク=きえる'],
    'over'  => ['OUT OF MEMORY', 'スペースキーで もういちど'],
  }

  def initialize_state
    @core = Allocator.new(COLS, ROWS)
    @tick = 0
    @flash_id = 0
    @armed = true
    @els = nil
    @shown = nil
    @board = nil
    @psegs = nil
    @mcells = nil
    @dragging = false
    @pc = false
    @record_flashed = false
    { phase: 'ready', score: 0, best: read_best, free: 100, flash: '', chain: 0,
      pc: false, title: '', record: false, over_en: '', over_ja: '' }
  end

  def component_mounted
    boot = JS.document.getElementById('boot')
    boot[:style][:display] = 'none' if boot
    @board = JS.document.querySelector('.board')
    @score_el = JS.document.querySelector('.hud-value')
    @pop_alt = false
    begin
      @pc = JS.global.matchMedia('(pointer: fine)')[:matches].to_s == 'true'
    rescue
      @pc = false
    end
    patch(pc: @pc) if @pc
    build_matrix
    build_pbar
    build_queue
    show_frame(@core.frame)
    show_queue
    JS.document.addEventListener('keydown') do |e|
      handle_key(e)
    end
    # The buttons via delegation: registered once, survives re-renders
    JS.document.addEventListener('click') do |e|
      target = e[:target]
      if target
        do_share if target.closest('.share-btn')
        rotate_action if target.closest('.rotate-btn')
      end
    end
  end

  # The LED matrix lives outside the vdom: built once, then the game loop
  # drives the cells directly (the same role as the board's LED driver)
  def build_matrix
    m = JS.document.querySelector('.matrix')
    return unless m
    m[:style].setProperty('--cols', COLS.to_s)
    m[:style].setProperty('--rows', ROWS.to_s)
    m[:innerHTML] = '<span class="cell c0"></span>' * (COLS * ROWS)
    @els = JS.document.querySelectorAll('.matrix .cell').to_a
    @shown = Array.new(COLS * ROWS, 0)
  end

  # The malloc deadline as LED segments under the heap: the program is
  # blocked on this call, and everyone can see how patient it feels
  def build_pbar
    pb = JS.document.querySelector('.pbar')
    return unless pb
    pb[:innerHTML] = '<span class="pseg"></span>' * 10
    @psegs = JS.document.querySelectorAll('.pseg').to_a
    @pshown = Array.new(10, '')
  end

  # NEXT window: the two queued tetrominoes as tiny 4x4 previews
  def build_queue
    q = JS.document.querySelector('.queue')
    return unless q
    mini = '<span class="mini">' + '<i class="mcell"></i>' * 16 + '</span>'
    q[:innerHTML] = '<span class="q-label">NEXT</span>' + mini * 2
    @mcells = JS.document.querySelectorAll('.mcell').to_a
  end

  # Diff the frame against what is on screen; rewrite only changed cells
  def show_frame(frame)
    return unless @els
    i = 0
    frame.each do |row|
      row.each do |code|
        if @shown[i] != code
          @shown[i] = code
          @els[i][:className] = CELL_CLASS[code]
        end
        i += 1
      end
    end
  end

  def show_patience
    return unless @psegs
    n = (@core.patience * 10 + @core.patience_max - 1) / @core.patience_max
    n = 0 if n < 0
    low = n <= 3
    i = 0
    @psegs.each do |el|
      cls = i < n ? (low ? 'pseg on low' : 'pseg on') : 'pseg'
      if @pshown[i] != cls
        @pshown[i] = cls
        el[:className] = cls
      end
      i += 1
    end
  end

  def show_queue
    return unless @mcells
    k = 0
    @core.queue.each do |req|
      break if k >= 2
      shape = Allocator::SHAPES[req[0]]
      on = req[1] == 1 ? 'mcell long' : 'mcell short'
      16.times do |j|
        dx = j % 4
        dy = j / 4
        has = false
        shape.each { |d| has = true if d[0] == dx && d[1] == dy }
        @mcells[k * 16 + j][:className] = has ? on : 'mcell'
      end
      k += 1
    end
  end

  # --- input ---------------------------------------------------------------

  def handle_key(e)
    code = e[:code].to_s
    case code
    when 'Space', 'Enter'
      e.preventDefault
      return if e[:repeat].to_s == 'true'
      state.phase == 'play' ? place_action : handle_tap(nil)
    when 'KeyR', 'KeyX'
      e.preventDefault
      state.phase == 'play' ? rotate_action : handle_tap(nil)
    when 'ArrowUp', 'KeyW'
      e.preventDefault
      steer(0, -1)
    when 'ArrowDown', 'KeyS'
      e.preventDefault
      steer(0, 1)
    when 'ArrowLeft', 'KeyA'
      e.preventDefault
      steer(-1, 0)
    when 'ArrowRight', 'KeyD'
      e.preventDefault
      steer(1, 0)
    end
  end

  def steer(dx, dy)
    return unless state.phase == 'play'
    if @core.move(dx, dy) == :moved
      sfx { |fx| fx.tick }
      show_frame(@core.frame)
    end
  end

  def rotate_action
    return unless state.phase == 'play'
    if @core.rotate == :rotated
      sfx { |fx| fx.tick }
      show_frame(@core.frame)
    end
  end

  # pointer position -> heap cell (nil if off the board, margin px of grace)
  def cell_at(ex, ey, margin)
    m = JS.document.querySelector('.matrix')
    return nil unless m
    r = m.getBoundingClientRect
    left = r[:left].to_f
    top = r[:top].to_f
    w = r[:width].to_f
    h = r[:height].to_f
    return nil if ex < left - margin || ex > left + w + margin ||
                  ey < top - margin || ey > top + h + margin
    cx = ((ex - left) * COLS / w).to_i
    cy = ((ey - top) * ROWS / h).to_i
    cx = 0 if cx < 0
    cy = 0 if cy < 0
    cx = COLS - 1 if cx > COLS - 1
    cy = ROWS - 1 if cy > ROWS - 1
    [cx, cy]
  end

  # Drag & drop: the finger picks the ghost up, the release drops the block
  def pointer_down(event)
    return unless event
    target = event[:target]
    return if target && target.closest('.share-btn, .rotate-btn')
    if state.phase == 'play'
      c = cell_at(event[:clientX].to_f, event[:clientY].to_f, 8)
      if c
        @dragging = true
        if @core.move_to(c[0], c[1]) == :moved
          sfx { |fx| fx.tick }
          show_frame(@core.frame)
        end
      end
      return
    end
    handle_tap(event)
  end

  def pointer_move(event)
    return unless event && @dragging && state.phase == 'play'
    c = cell_at(event[:clientX].to_f, event[:clientY].to_f, 40)
    return unless c
    if @core.move_to(c[0], c[1]) == :moved
      show_frame(@core.frame)
    end
  end

  def pointer_up(event)
    return unless @dragging
    @dragging = false
    return unless event
    return unless state.phase == 'play'
    # release off the board = put the ghost back down without placing
    c = cell_at(event[:clientX].to_f, event[:clientY].to_f, 40)
    return unless c
    place_action
  end

  def handle_tap(_event)
    case state.phase
    when 'ready'
      start_game
    when 'over'
      # a short cooldown so the final reflex tap doesn't skip the result
      return unless @armed
      @core.reset
      show_frame(@core.frame)
      show_queue
      patch(phase: 'ready', score: 0, free: @core.free_pct, flash: '', chain: 0)
    end
  end

  # --- game loop -------------------------------------------------------------

  def start_game
    @core.reset
    @tick += 1
    @record_flashed = false
    sfx { |fx| fx.start }
    show_frame(@core.frame)
    show_queue
    show_patience
    patch(phase: 'play', score: 0, free: @core.free_pct, flash: '', chain: 0,
          record: false)
    schedule_step
  end

  def schedule_step
    id = @tick
    JS.global.setTimeout(@core.interval) do
      if id == @tick && @core.phase == :play
        result = @core.step
        show_frame(@core.frame)
        show_patience
        case result
        when :autoplace
          # the machine placed it for you, top-left first-fit, zero
          # bytes. Same soft thud as a blocked drop -- a letdown, not
          # a punishment
          sfx { |fx| fx.deny }
          flash_msg('FIRST FIT...')
          show_queue
          patch(chain: 0, free: @core.free_pct)
        when :over
          sfx { |fx| fx.over }
          finish
        else
          pct = @core.free_pct
          patch(free: pct) if pct != state.free
        end
        check_record
        schedule_step if @core.phase == :play
      end
    end
  end

  def place_action
    return unless state.phase == 'play'
    case @core.place
    when :harvest
      # the crunch: the combo count is the celebration tier. x4 is the
      # I-piece moment -- give it everything
      n = @core.last_combo
      case n
      when 1
        sfx { |fx| fx.lock(4) }
        flash_msg("かいしゅう +#{@core.last_salvage}bytes")
      when 2
        sfx { |fx| fx.perfect(4) }
        flash_msg("ダブル！ +#{@core.last_salvage}bytes")
        board_pulse
      when 3
        sfx { |fx| fx.perfect(8) }
        flash_msg("トリプル！ +#{@core.last_salvage}bytes")
        board_pulse
      else
        sfx { |fx| fx.win }
        flash_msg("テトラかいしゅう！！ +#{@core.last_salvage}bytes")
        board_pulse
      end
      sweep_juice(@core.last_salvage)
      after_place
    when :perfect
      sfx { |fx| fx.perfect(@core.chain) }
      sweep_juice(@core.last_alloc + @core.last_bonus)
      flash_msg("ぴったり！ +#{@core.last_bonus}bytes")
      board_pulse
      after_place
    when :placed
      sfx { |fx| fx.lock(@core.chain) }
      sweep_juice(@core.last_alloc)
      after_place
    when :blocked
      # a soft low thud: audible, never grating
      sfx { |fx| fx.deny }
    end
  end

  def after_place
    show_frame(@core.frame)
    show_queue
    show_patience
    patch(score: @core.score, chain: @core.chain, free: @core.free_pct)
    # this placement filled the heap past the line: the next request
    # has nowhere to go and the game just ended
    if @core.phase == :over
      sfx { |fx| fx.over }
      finish
    end
  end

  # Juice on allocate: the score digit thumps in the HUD, and the points
  # float up from where the block landed
  def sweep_juice(bytes)
    if @score_el
      @pop_alt = !@pop_alt
      @score_el[:className] = @pop_alt ? 'hud-value pop' : 'hud-value pop2'
    end
    float_score(bytes)
  end

  def float_score(bytes)
    m = JS.document.querySelector('.matrix')
    return unless @board && m
    br = @board.getBoundingClientRect
    mr = m.getBoundingClientRect
    gc = @core.ghost_cell
    x = mr[:left].to_f - br[:left].to_f + (gc[0] + 0.5) * (mr[:width].to_f / COLS)
    y = mr[:top].to_f - br[:top].to_f + gc[1] * (mr[:height].to_f / ROWS)
    el = JS.document.createElement('div')
    el[:className] = 'float-score'
    el[:textContent] = "+#{bytes}"
    el[:style][:left] = "#{x.to_i}px"
    el[:style][:top] = "#{y.to_i}px"
    @board.appendChild(el)
    JS.global.setTimeout(700) { el.remove }
  end

  # Juice: the whole heap thumps on a perfect fit
  def board_pulse
    return unless @board
    @board[:className] = 'board pulse'
    JS.global.setTimeout(280) { @board[:className] = 'board' }
  end

  def shake
    return unless @board
    @board[:className] = 'board shake-big'
    JS.global.setTimeout(420) { @board[:className] = 'board' }
  end

  def finish
    @tick += 1
    @armed = false
    JS.global.setTimeout(700) { @armed = true }
    record = state.best > 0 && @core.score > state.best
    save_best(@core.score)
    show_frame(@core.frame)
    shake
    oja = if @core.death == :oom_frag
            'だんぺんかで すきまが たりない！ タップで もういちど'
          else
            'ヒープが あふれた！ タップで もういちど'
          end
    patch(phase: 'over', score: @core.score, flash: '', chain: 0, free: @core.free_pct,
          title: title_for(@core.score), record: record,
          over_en: 'OUT OF MEMORY', over_ja: oja)
  end

  # The moment worth a screenshot: flash the instant the personal best falls
  def check_record
    return if @record_flashed
    return unless state.best > 0 && state.phase == 'play'
    if @core.score > state.best
      @record_flashed = true
      sfx { |fx| fx.perfect(11) }
      flash_msg('🏆 NEW RECORD!')
    end
  end

  def flash_msg(text)
    @flash_id += 1
    id = @flash_id
    patch(flash: text)
    JS.global.setTimeout(800) do
      if id == @flash_id && state.phase == 'play'
        patch(flash: '', score: @core.score)
      end
    end
  end

  def sfx
    fx = JS.global[:gameSfx]
    yield fx if fx
  end

  # Same score, different play, different title. Each playstyle gets its
  # own shape: prefix, epithet, annotation, feat or tag.
  def title_for(score)
    base = ''
    TITLES.each do |t|
      if score >= t[0]
        names = t[1]
        base = names[(score + @core.ticks) % names.size]
        break
      end
    end
    return "#{base}、のこり#{@core.free_pct}%" if @core.free_pct <= 15
    return "#{base} 〜テトラかいしゅうの きわみ〜" if @core.max_combo >= 4
    return "はやわざの #{base}" if @core.ticks < 250 && score >= 800
    return "#{base} 〜ぴったりの きわみ〜" if @core.max_chain >= 6
    return "こまめな #{base}" if @core.ticks >= 400 && score >= 3000
    return "#{base}・ロングラン" if @core.ticks >= 700
    base
  end

  def read_best
    v = JS.global[:localStorage].getItem(BEST_KEY)
    v.nil? ? 0 : v.to_s.to_i
  end

  def save_best(score)
    return if score <= state.best
    JS.global[:localStorage].setItem(BEST_KEY, score.to_s)
    patch(best: score)
  end

  # --- share -----------------------------------------------------------------

  def do_share
    return unless state.phase == 'over'
    JS.global.shareResult(share_text)
  end

  def share_text
    lines = []
    lines << '🧩 MALLOC PANIC - PicoRubyKaigi 2026'
    lines << "#{state.score} bytes 「#{state.title}」"
    lines.concat(emoji_grid)
    lines << '#PicoRubyKaigi'
    lines.join("\n")
  end

  # The final heap as a compact emoji picture: your own crash site is the
  # shareable artifact
  def emoji_grid
    f = @core.frame
    sx = (COLS + 11) / 12
    sy = (ROWS + 9) / 10
    rows = []
    filled = []
    y = 0
    while y < ROWS
      line = ''
      any = false
      x = 0
      while x < COLS
        code = 0
        yy = y
        while yy < y + sy && yy < ROWS
          xx = x
          while xx < x + sx && xx < COLS
            c = f[yy][xx]
            code = c if c > code
            xx += 1
          end
          yy += 1
        end
        any = true if code > 0
        line << (EMOJI[code] || '⬛')
        x += sx
      end
      rows << line
      filled << any
      y += sy
    end
    rows.pop while rows.size > 1 && !filled[rows.size - 1]
    while rows.size > 1 && !filled[0]
      rows.shift
      filled.shift
    end
    rows
  end

  # --- view --------------------------------------------------------------------
  # The DOM structure is identical in every phase (visibility is CSS-only);
  # the matrix cells, patience bar and queue live outside the vdom entirely.

  def render
    msgs = state.pc ? MESSAGES_PC : MESSAGES_TOUCH
    msg = msgs[state.phase] || ['', '']
    div(class: "game phase-#{state.phase}",
        onpointerdown: :pointer_down, onpointermove: :pointer_move,
        onpointerup: :pointer_up) do
      div(class: 'hud') do
        div(class: 'hud-item') do
          span(class: 'hud-label') { 'BYTES' }
          span(class: 'hud-value') { state.score.to_s }
        end
        div(class: 'hud-item') do
          span(class: 'hud-label') { 'FREE' }
          span(class: 'hud-value') { "#{state.free}%" }
        end
        div(class: 'hud-item') do
          span(class: 'hud-label') { 'BEST' }
          span(class: 'hud-value') { state.best.to_s }
        end
      end
      div(class: 'queue')
      div(class: 'board') do
        div(class: 'matrix')
        div(class: 'pbar')
      end
      div(class: 'msg') do
        if state.phase == 'play'
          div(class: state.flash == '' ? 'msg-en' : 'msg-en msg-flash') { state.flash }
          div(class: state.chain >= 2 ? 'msg-ja msg-chain' : 'msg-ja') do
            state.chain >= 2 ? "れんぞく ぴったり x#{state.chain}" : (msg[1] || '')
          end
        else
          oen = state.phase == 'over' && state.over_en != '' ? state.over_en : nil
          oja = state.phase == 'over' && state.over_ja != '' ? state.over_ja : nil
          div(class: 'msg-en') { oen || msg[0] || '' }
          div(class: 'msg-ja') { oja || msg[1] || '' }
        end
        div(class: 'msg-record') do
          state.phase == 'over' && state.record ? '🏆 NEW RECORD!' : ''
        end
        div(class: 'msg-title') do
          state.phase == 'over' && state.title != '' ? "しょうごう「#{state.title}」" : ''
        end
      end
      div(class: 'actions') do
        button(class: 'rotate-btn') { '↻ かいてん' }
        button(class: 'share-btn') { '📣 けっかを シェア' }
      end
    end
  end
end

Funicular.start(App, container: 'app')
