require 'js'

# GC PANIC のフロントエンド: 状態機械(ready → play → over)・入力・
# ゲームループを持つ Funicular コンポーネント。
#   sweeper.rb     - Rubyのゲームコア
#   titles.rb      - スコア → 称号
#   matrix_view.rb - LEDマトリクスのドライバ(vdomの外のDOM)
#   fx.rb          - 効果音・シェイク・フロート表示
#   share_card.rb  - Xポスト文面
class App < Funicular::Component
  MESSAGES_TOUCH = {
    'ready' => ['TAP TO START', '外タップで左右・内タップで上下', 'グレーのゴミだけ掃除'],
    'play'  => ['', 'グレーのゴミだけ掃除'],
    'over'  => ['SEGV', ''],
  }

  MESSAGES_PC = {
    'ready' => ['PRESS SPACE', '矢印キーで移動・スペースで FULL GC', 'グレーのゴミだけ掃除'],
    'play'  => ['', '矢印キーで掃除・スペースで FULL GC'],
    'over'  => ['SEGV', ''],
  }

  def initialize_state
    @core = Sweeper.new(10, 10)
    @tick = 0
    @flash_id = 0
    @armed = true
    @ptr_x = 0.0
    @ptr_y = 0.0
    @dragging = false
    @drag_steered = false
    @down_in_game = false
    @pc = false
    @record_flashed = false
    @frag_cd = 0
    @gc_hinted = false
    @collected = read_collection
    v = JS.global[:localStorage].getItem('gc-panic-slow')
    @yukkuri = v.nil? ? true : v.to_s == '1'
    { phase: 'ready', score: 0, best: read_best, free: 100, flash: '', chain: 0,
      pc: false, title: '', record: false, over_en: '', over_ja: '', gcbusy: false,
      gchint: false, zukan: false, info: false, comp: collection_complete?,
      yukkuri: @yukkuri }
  end

  def component_mounted
    boot = JS.document.getElementById('boot')
    boot[:style][:display] = 'none' if boot
    @view = MatrixView.new(@core.cols, @core.rows)
    @fx = Fx.new
    begin
      @pc = JS.global.matchMedia('(pointer: fine)')[:matches].to_s == 'true'
    rescue
      @pc = false
    end
    patch(pc: @pc) if @pc
    @view.show(@core.frame)
    JS.document.addEventListener('keydown') do |e|
      handle_key(e)
    end
    # ポインタ追跡はすべて document で行う: スワイプは .game 要素の外へ
    # はみ出すことがあるため
    JS.document.addEventListener('pointerdown') do |e|
      pointer_down(e)
    end
    JS.document.addEventListener('pointermove') do |e|
      pointer_move(e)
    end
    JS.document.addEventListener('pointerup') do |e|
      handle_pointer_up(e)
    end
    JS.document.addEventListener('pointercancel') do |e|
      @dragging = false
    end
    # ボタンは委譲(delegation)で: 登録は一度きり、再レンダリングでも生きる
    JS.document.addEventListener('click') do |e|
      target = e[:target]
      if target
        do_share if target.closest('.share-btn')
        full_gc_action if target.closest('.gcstart-btn')
        patch(zukan: !state.zukan) if target.closest('.zukan-btn')
        toggle_yukkuri if target.closest('.slow-btn')
        patch(info: !state.info) if target.closest('.info-btn')
        patch(info: false) if state.info && target.closest('.zukan')
        patch(zukan: false) if state.zukan && target.closest('.zukan')
      end
    end
  end

  # input

  def handle_key(e)
    code = e[:code].to_s
    case code
    when 'Space', 'Enter'
      e.preventDefault
      return if e[:repeat].to_s == 'true'
      state.phase == 'play' ? full_gc_action : handle_tap(nil)
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
    if @core.turn(dx, dy) == :turned
      @fx.sfx { |fx| fx.tick }
      @view.flash_turn(@core)
    end
  end

  def pointer_down(event)
    return unless event
    target = event[:target]
    return if target && target.closest('.share-btn, .gcstart-btn, .zukan-btn, .zukan, .slow-btn, .info-btn, a')
    if state.phase == 'play'
      @ptr_x = event[:clientX].to_f
      @ptr_y = event[:clientY].to_f
      @dragging = true
      @drag_steered = false
    else
      return unless target && target.closest('.game')
      @down_in_game = true
      @ptr_x = event[:clientX].to_f
      @ptr_y = event[:clientY].to_f
    end
  end

  def handle_pointer_up(event)
    if state.phase == 'play'
      pointer_up(event) if @dragging
    elsif @down_in_game
      @down_in_game = false
      pointer_up(event)
    end
  end

  # フローティングジョイスティック: 指を置いたまま、(随時アンカーし直す)
  # 原点から約10pxずれるたびに箒が曲がる。親指の微動だけ、遅延なし。
  def pointer_move(event)
    return unless event && @dragging && state.phase == 'play'
    x = event[:clientX].to_f
    y = event[:clientY].to_f
    dx = x - @ptr_x
    dy = y - @ptr_y
    adx = dx < 0 ? -dx : dx
    ady = dy < 0 ? -dy : dy
    return if adx < 10 && ady < 10
    if adx > ady
      steer(dx > 0 ? 1 : -1, 0)
    else
      steer(0, dy > 0 ? 1 : -1)
    end
    @drag_steered = true
    @ptr_x = x
    @ptr_y = y
  end

  def pointer_up(event)
    @dragging = false
    return unless event
    target = event[:target]
    return if target && target.closest('.share-btn, .zukan-btn, .zukan, .slow-btn, .info-btn')
    dx = event[:clientX].to_f - @ptr_x
    dy = event[:clientY].to_f - @ptr_y
    adx = dx < 0 ? -dx : dx
    ady = dy < 0 ? -dy : dy
    unless state.phase == 'play'
      # 開始/再開は本物のタップのみ。スクロールでは発動しない:
      # リザルト画面でシェアボタンへスクロールしても再開してはならない
      handle_tap(event) if adx < 12 && ady < 12
      return
    end
    return if @drag_steered
    if adx < 10 && ady < 10
      # 親指ごとのミラー十字:
      #   |← |↑↓ |→ |← |↑↓ |→ |
      w = JS.global[:innerWidth].to_f
      ex = event[:clientX].to_f
      band = ex / w
      if band < 0.15 || (band >= 0.5 && band < 0.65)
        steer(-1, 0)
      elsif band >= 0.85 || (band >= 0.35 && band < 0.5)
        steer(1, 0)
      else
        mid = JS.global[:innerHeight].to_f
        m = JS.document.querySelector('.matrix')
        if m
          mb = m.getBoundingClientRect[:bottom].to_f
          mid = (mb + mid) / 2
        else
          mid = mid * 0.55
        end
        steer(0, event[:clientY].to_f < mid ? -1 : 1)
      end
      return
    end
    if adx > ady
      steer(dx > 0 ? 1 : -1, 0)
    else
      steer(0, dy > 0 ? 1 : -1)
    end
  end

  def handle_tap(_event)
    case state.phase
    when 'ready'
      start_game
    when 'over'
      # 死亡直前の反射タップでリザルトが飛ばないよう、短いクールダウン
      return unless @armed
      @core.reset
      @view.show(@core.frame)
      patch(phase: 'ready', score: 0, free: @core.free_pct, flash: '', chain: 0)
    end
  end

  # game loop

  def start_game
    @core.reset
    @tick += 1
    @record_flashed = false
    # プレイ中はどこで始まるスワイプでもページをスクロールさせない——
    # 盤面の外からのスワイプも含む(body.playing が touch-action を殺す)
    JS.document[:body][:classList].add('playing')
    @fx.sfx { |fx| fx.start }
    @view.show(@core.frame)
    patch(phase: 'play', score: 0, free: @core.free_pct, flash: '', chain: 0, record: false)
    schedule_step
  end

  def schedule_step
    id = @tick
    JS.global.setTimeout(step_interval) do
      if id == @tick && @core.phase == :play
        prev = @core.player_cell
        result = @core.step
        @view.show(@core.frame)
        @view.mark_barrier(@core)
        @view.mark_wrap(@core)
        @view.mark_pending(@core)
        cur = @core.player_cell
        jx = cur[0] - prev[0]
        jy = cur[1] - prev[1]
        @view.warp_pop(@core) if jx > 1 || jx < -1 || jy > 1 || jy < -1
        case result
        when :sweep
          @fx.sfx { |fx| fx.lock(@core.chain) }
          @fx.sfx { |fx| fx.kyui(@core.chain) } if @core.chain >= 2
          @fx.sweep(@core)
          if @core.chain > 0 && @core.chain % 5 == 0
            @fx.sfx { |fx| fx.perfect(@core.chain) }
            flash_msg("がったい x#{@core.chain}！")
            @fx.pulse
            @fx.confetti(@core)
          end
          patch(score: @core.score, chain: @core.chain, free: @core.free_pct)
        when :barrier
          @fx.sfx { |fx| fx.crack }
          flash_msg('WRITE BARRIER!')
          patch(chain: 0)
        when :over
          @fx.sfx { |fx| fx.over }
          finish
        else
          # 破滅の時計: オブジェクトが積もるにつれヒープ使用量が画面で這い上がる
          pct = @core.free_pct
          patch(free: pct) if pct != state.free
        end
        busy = !@core.gc_ready?
        patch(gcbusy: busy) if busy != state.gcbusy
        if !@gc_hinted && @core.gc_starts == 0 && @core.ticks > 60 &&
           @core.garbage_count >= 6
          @gc_hinted = true
          patch(gchint: true)
          JS.global.setTimeout(6000) { patch(gchint: false) if state.phase == 'play' }
        end
        # アロケータが置き場所に苦労している = 断片化の警告。
        # 死因になる前に知らせる
        @frag_cd -= 1 if @frag_cd > 0
        if @core.phase == :play && @core.last_tries > 28 && @frag_cd <= 0
          @frag_cd = 60
          flash_msg('FRAGMENTED!')
        end
        check_record
        schedule_step if @core.phase == :play
      end
    end
  end

  def full_gc_action
    return unless state.phase == 'play'
    case @core.full_gc
    when :fullgc
      @fx.sfx { |fx| fx.win }
      @fx.stw_flash
      flash_msg('STOP THE WORLD')
      @view.show(@core.frame)
      patch(score: @core.score, chain: 0, free: @core.free_pct, gcbusy: true, gchint: false)
      freed = @core.last_freed
      JS.global.setTimeout(780) { flash_msg("FULL GC +#{freed}bytes") if state.phase == 'play' }
    when :cooldown
      flash_msg('GC BUSY...')
    end
  end

  def finish
    @tick += 1
    @armed = false
    JS.document[:body][:classList].remove('playing')
    JS.global.setTimeout(700) { @armed = true }
    record = state.best > 0 && @core.score > state.best
    save_best(@core.score)
    @view.show(@core.frame)
    @fx.shake(@core.death)
    oen = ''
    oja = ''
    if @core.death == :oom_full
      oen = 'OUT OF MEMORY'
      oja = 'ヒープがあふれた！'
    elsif @core.death == :oom_frag
      oen = 'OUT OF MEMORY'
      oja = '断片化ですきまが足りない！'
    end
    was_complete = state.comp
    save_collection(Titles.tier_for(@core)[1])
    complete = collection_complete?
    patch(phase: 'over', score: @core.score, flash: '', chain: 0, free: @core.free_pct,
          title: Titles.pick(@core), record: record, over_en: oen, over_ja: oja,
          comp: complete)
    # コレクションを完成させたそのランには、死亡ジングルが鳴り終わった
    # 直後に遅れてファンファーレが鳴る
    if complete && !was_complete
      JS.global.setTimeout(900) { @fx.sfx { |fx| fx.win } }
    end
  end

  def check_record
    return if @record_flashed
    return unless state.best > 0 && state.phase == 'play'
    if @core.score > state.best
      @record_flashed = true
      @fx.sfx { |fx| fx.perfect(11) }
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

  # best / share

  def best_key
    @yukkuri ? "gc-panic-best-#{@core.cols}-slow" : "gc-panic-best-#{@core.cols}"
  end

  def read_best
    v = JS.global[:localStorage].getItem(best_key)
    v.nil? ? 0 : v.to_s.to_i
  end

  def save_best(score)
    return if score <= state.best
    JS.global[:localStorage].setItem(best_key, score.to_s)
    patch(best: score)
  end

  COLLECT_TITLES_KEY = 'gc-panic-titles'

  def read_collection
    v = JS.global[:localStorage].getItem(COLLECT_TITLES_KEY)
    v.nil? ? [] : v.to_s.split('|')
  end

  def save_collection(name)
    return if name == '' || @collected.include?(name)
    @collected << name
    JS.global[:localStorage].setItem(COLLECT_TITLES_KEY, @collected.join('|'))
  end

  def toggle_yukkuri
    return if state.phase == 'play'
    @yukkuri = !@yukkuri
    JS.global[:localStorage].setItem('gc-panic-slow', @yukkuri ? '1' : '0')
    patch(yukkuri: @yukkuri, best: read_best)
  end

  def step_interval
    ms = @core.interval
    @yukkuri ? ms * 2 : ms
  end

  def collection_complete?
    Titles::TIERS.each do |t|
      t[1].each { |n| return false unless @collected.include?(n) }
    end
    true
  end

  def do_share
    return unless state.phase == 'over'
    JS.global.shareResult(ShareCard.text(state.score, state.title, @core, @yukkuri))
  end

  # view
  # DOM構造は全フェーズで同一(表示切替はCSSのみ)。
  # マトリクスのセルは完全にvdomの外にいる。

  def render
    msgs = state.pc ? MESSAGES_PC : MESSAGES_TOUCH
    msg = msgs[state.phase] || ['', '']
    cls = "game phase-#{state.phase}"
    cls += ' pc' if state.pc
    div(class: cls) do
      div(class: 'title') do
        span(class: 't-lamp') { '' }
        span { 'GC PANIC' }
      end
      button(class: 'info-btn') { 'ⓘ' }
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
        # HUD内・操舵ゾーンの外に置く: 画面中央下は「↓タップ」の一等地で、
        # そこにボタンがあるとタップを飲み込んでしまった
        gc_cls = state.gcbusy ? 'gcstart-btn busy' : 'gcstart-btn'
        gc_cls += ' hint' if state.gchint && !state.gcbusy
        button(class: gc_cls) { 'FULL GC' }
      end
      div(class: 'board') do
        div(class: 'matrix')
      end
      div(class: 'msg') do
        if state.phase == 'play'
          div(class: state.flash == '' ? 'msg-en' : 'msg-en msg-flash') { state.flash }
          # cp0/cp1 クラスを交互に切り替えて、リンクのたびに pop を再発火させる
          chain_cls = "msg-ja msg-chain cp#{state.chain % 2}"
          chain_cls += ' hot' if state.chain >= 5
          div(class: state.chain >= 2 ? chain_cls : 'msg-ja') do
state.chain >= 2 ? "がったい ×#{state.chain}（スコア#{state.chain > 8 ? 8 : state.chain}倍）" : (msg[1] || '')
          end
        else
          oen = state.phase == 'over' && state.over_en != '' ? state.over_en : nil
          oja = state.phase == 'over' && state.over_ja != '' ? state.over_ja : nil
          div(class: 'msg-en') { oen || msg[0] || '' }
          div(class: 'msg-ja') { oja || msg[1] || '' }
          div(class: 'msg-ja') { state.phase == 'ready' ? (msg[2] || '') : '' }
        end
        div(class: 'msg-record') do
          state.phase == 'over' && state.record ? '🏆 NEW RECORD!' : ''
        end
        div(class: 'msg-title') do
          state.phase == 'over' && state.title != '' ? "称号 #{state.title}" : ''
        end
        div(class: 'msg-comp') do
          state.phase == 'over' && state.comp ? '👑 全称号コンプリート！' : ''
        end
      end
      div(class: 'actions') do
        button(class: 'share-btn') { '🏆 称号をシェア' }
        button(class: 'zukan-btn') { '📖 コレクション' }
        button(class: state.yukkuri ? 'slow-btn on' : 'slow-btn') { '🐢 ゆっくり' }
      end
      if state.info
        div(class: 'zukan') do
          div(class: 'zukan-inner') do
            div(class: 'zukan-title') { 'そうさ方法' }
            div(class: 'zmap') do
              div(class: 'zm-side') { '←' }
              div(class: 'zm-mid') do
                div(class: 'zm-cell') { '↑' }
                div(class: 'zm-cell') { '↓' }
              end
              div(class: 'zm-side') { '→' }
            end
            div(class: 'info-line') { '盤面の下をタップ: はしで左右・内側で上下' }
            div(class: 'info-line') { 'スワイプでも動かせる' }
            div(class: 'info-line') { 'FULL GC: 右上のボタン(全ゴミを半額で回収)' }
            div(class: 'zukan-close') { 'タップで閉じる' }
          end
        end
      end
      if state.zukan
        div(class: 'zukan') do
          div(class: 'zukan-inner') do
            div(class: 'zukan-title') do
              state.comp ? '👑 コンプリート！すべての称号を集めた' : '手に入れた称号'
            end
            Titles::TIERS.each do |t|
              got = []
              t[1].each { |n| got << n if @collected.include?(n) }
              div(class: got.empty? ? 'zk-row zk-locked' : 'zk-row') do
                span(class: 'zk-emoji') { got.empty? ? '❔' : t[2] }
                span(class: 'zk-name') do
                  got.empty? ? '？？？' : got.join(' ／ ')
                end
              end
            end
            div(class: 'zukan-close') { 'タップで閉じる' }
          end
        end
      end
    end
  end
end

Funicular.start(App, container: 'app')
