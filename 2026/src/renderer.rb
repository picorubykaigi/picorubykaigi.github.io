require 'erb'
require 'cgi'

module Renderer
  SITE = 'https://picorubykaigi.org'
  TEMPLATES = File.join(__dir__, 'templates')

  class << self
    def render(name, **locals)
      b = binding
      locals.each { |key, value| b.local_variable_set(key, value) }
      ERB.new(File.read(File.join(TEMPLATES, name)), trim_mode: '-').result(b)
    end

    def partial(name, **locals)
      render(name, **locals).chomp
    end

    def escape(text)
      CGI.escapeHTML(text.to_s)
    end
  end
end
