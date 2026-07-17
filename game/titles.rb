class Titles
  TIERS = [
    [8960, ['GCの とくいてん', 'メモリの ビッグバン'], '🌌'],
    [7168, ['うちゅうの そうじや', 'ぎんがの GC'], '🛸'],
    [5760, ['でんせつの GC', 'ヒープの きゅうせいしゅ'], '🦸'],
    [4608, ['GCの かみさま', 'メモリの せいれい'], '⛩️'],
    [3712, ['そうじの てつじん', 'ヒープの けんじゃ'], '🧙'],
    [2944, ['だんぺんか キラー', 'れんぞくかいほう おう'], '💥'],
    [2304, ['メモリの まもりびと', 'ヒープの ばんにん'], '🛡️'],
    [1792, ['ベテラン GC', 'うでっこき そうじにん'], '💪'],
    [1344, ['ヒープの ぬし', 'ろじうらの ボス'], '👑'],
    [960, ['げんば かんとく', 'そうじ はんちょう'], '🧢'],
    [704, ['はたらく GC', 'コツコツがんばりや'], '🧹'],
    [512, ['まちの そうじや', 'ほうき デビュー'], '🏠'],
    [320, ['みならい GC', 'そうじ れんしゅうちゅう'], '🔰'],
    [128, ['ちりとり がかり', 'ひろいやさん'], '🗑️'],
    [0, ['うごく そうじき', 'よちよち ほうき'], '🤖'],
  ]

  def self.tier_for(core)
    score = core.score
    TIERS.each do |t|
      next unless score >= t[0]
      return [t[2], t[1][(score + core.ticks) % t[1].size]]
    end
    ['', '']
  end

  def self.pick(core)
    score = core.score
    emoji, base = tier_for(core)
    decorated = case
    when core.free_pct <= 15
      "#{base}、のこり#{core.free_pct}%"
    when core.max_chain >= 12
      "#{base} 〜がったいの きわみ〜"
    when core.barrier_saves == 0 && score >= 960
      "むきずの #{base}"
    when core.gc_starts == 0 && score >= 960
      "こまめな #{base}"
    when core.ticks >= 560
      "#{base}・ロングラン"
    else
      base
    end
    "#{emoji}「#{decorated}」"
  end
end
