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

  def pending_cells
    @pending ? @pending[2] : nil
  end

  def garbage_count
    n = 0
    @objs.each { |id, o| n += 1 if o[0] == :garbage }
    n
  end

  def free_pct
    used = 0
    @rows.times { |y| @cols.times { |x| used += 1 if @grid[y][x] } }
    100 - (used * 100) / (@cols * @rows)
  end

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
    @stw = 5
    :fullgc
  end

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

  def advance_sweeper
    if @stun > 0
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
    bytes += 4 if @chain >= 2
    mult = @chain > 8 ? 8 : @chain
    bytes *= mult if mult > 1
    @score += bytes
    @last_freed = bytes
    @empty_run = 0
    :sweep
  end

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

  def age_objects
    expired = []
    @since_mark += 1
    @objs.each do |oid, o|
      if o[0] == :live
        o[1] -= 1
        if o[1] <= 0
          o[0] = :garbage
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

  def force_mark_if_dry
    return unless @since_mark > 12 && garbage_count < 3
    victim = nil
    @objs.each do |_oid, o|
      victim = o if o[0] == :live && (victim.nil? || o[1] < victim[1])
    end
    victim[1] = 3 if victim && victim[1] > 3
  end

  def program_allocates
    return true if allocate
    used = 0
    @rows.times { |y| @cols.times { |x| used += 1 if @grid[y][x] } }
    @death = used >= (@cols * @rows * 85) / 100 ? :oom_full : :oom_frag
    @phase = :over
    false
  end

  def alloc_every
    return 8 if @tick < 150
    e = 6 - @level / 2
    e < 3 ? 3 : e
  end

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
              r % 2 == 0 ? SHAPES[4] : SHAPES[5]
            end
    bytes = shape.size == 1 ? 24 : (shape.size == 2 ? 56 : (shape.size == 4 ? 96 : 192))
    p = 100 - (@tick - 150) / 4
    p = 40 if p < 40
    if rand_n(100) < p
      ttl = 10 + rand_n(25)
    else
      ttl = 30 + rand_n(70) + @level * 6
    end
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
