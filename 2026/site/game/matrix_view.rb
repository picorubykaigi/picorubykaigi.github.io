require 'js'

class MatrixView
  CELL_CLASS = ['cell c0', 'cell c1', 'cell c2', 'cell c3', 'cell c4',
                'cell c5', 'cell c6', 'cell c7', 'cell c8']

  def initialize(cols, rows)
    @cols = cols
    @rows = rows
    @was_down = false
    @ghost_i = nil
    @pend_is = []
    m = JS.document.querySelector('.matrix')
    return unless m
    m[:style].setProperty('--cols', cols.to_s)
    m[:style].setProperty('--rows', rows.to_s)
    m[:innerHTML] = '<span class="cell c0"></span>' * (cols * rows)
    @els = JS.document.querySelectorAll('.cell').to_a
    @shown = Array.new(cols * rows, 0)
  end

  def show(frame)
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

  def flash_turn(core)
    return unless @els
    pc = core.player_cell
    i = pc[1] * @cols + pc[0]
    @els[i][:className] = core.barrier_down? ? 'cell c2 turn nobarrier' : 'cell c2 turn'
  end

  def mark_wrap(core)
    return unless @els
    if @ghost_i
      @els[@ghost_i][:className] = CELL_CLASS[@shown[@ghost_i]]
      @ghost_i = nil
    end
    nc = core.wrap_landing
    return unless nc
    i = nc[1] * @cols + nc[0]
    @els[i][:className] = CELL_CLASS[@shown[i]] + ' ghost'
    @ghost_i = i
  end

  def mark_pending(core)
    return unless @els
    cells = core.pending_cells
    wanted = []
    if cells
      cells.each do |c|
        i = c[1] * @cols + c[0]
        wanted << i if @shown[i] == 0
      end
    end
    return if wanted == @pend_is
    @pend_is.each { |i| @els[i][:className] = CELL_CLASS[@shown[i]] }
    wanted.each { |i| @els[i][:className] = CELL_CLASS[0] + ' incoming' }
    @pend_is = wanted
  end

  def warp_pop(core)
    return unless @els
    pc = core.player_cell
    i = pc[1] * @cols + pc[0]
    @els[i][:className] = core.barrier_down? ? 'cell c2 warp nobarrier' : 'cell c2 warp'
  end

  def mark_barrier(core)
    return unless @els
    down = core.barrier_down?
    pc = core.player_cell
    i = pc[1] * @cols + pc[0]
    if down
      @els[i][:className] = 'cell c2 nobarrier'
    elsif @was_down
      @els[i][:className] = 'cell c2'
    end
    @was_down = down
  end
end
