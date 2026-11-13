#!/usr/bin/env ruby
#
# Replaces all of Cloudflare's Redirect Rules with the rules this script builds.
#
#   bundle exec ruby build.rb && ruby tools/cloudflare_redirects.rb           # list the redirects
#   ruby tools/cloudflare_redirects.rb --json                                 # show the JSON sent to Cloudflare
#   CLOUDFLARE_API_TOKEN=... CLOUDFLARE_ZONE_ID=... ruby tools/cloudflare_redirects.rb --apply
#
# The API token needs the Single Redirect (formerly Dynamic Redirect) Edit permission on the picorubykaigi.org zone.

require 'json'
require 'net/http'
require 'uri'

class CloudflareRedirects
  SITE = 'https://picorubykaigi.org'
  CURRENT_YEAR = '2026'
  LEGACY_YEAR = '2026'
  ENDPOINT = 'https://api.cloudflare.com/client/v4/zones/%s/rulesets/phases/http_request_dynamic_redirect/entrypoint'

  def initialize(root)
    @root = root
  end

  def rules
    [top_rule, legacy_rule]
  end

  def summary
    directories, files = legacy_entries
    legacy = directories.map { |entry| "/#{entry}/..." } + files.map { |entry| "/#{entry}" }
    lines = [[302, '/', "#{SITE}/#{CURRENT_YEAR}/"]] + legacy.map { |from| [301, from, "#{SITE}/#{LEGACY_YEAR}#{from}"] }
    width = lines.map { |_, from, _| from.size }.max
    lines.map.with_index do |(status, from, to), index|
      "  #{status}  #{from.ljust(width)}  -> #{to}"
    end
  end

  def apply(token:, zone:)
    uri = URI(format(ENDPOINT, zone))
    request = Net::HTTP::Put.new(uri, 'Authorization' => "Bearer #{token}", 'Content-Type' => 'application/json')
    request.body = JSON.generate(rules: rules)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
    result = JSON.parse(response.body)
    abort("Cloudflare API: #{response.code} #{JSON.pretty_generate(result['errors'])}") unless result['success']

    result['result']['rules'].size
  end

  private

  def top_rule
    {
      description: "Top -> /#{CURRENT_YEAR}/",
      expression: 'http.request.uri.path eq "/"',
      action: 'redirect',
      action_parameters: {
        from_value: { status_code: 302, target_url: { value: "#{SITE}/#{CURRENT_YEAR}/" }, preserve_query_string: true }
      }
    }
  end

  def legacy_rule
    {
      description: "#{LEGACY_YEAR} site at the root -> /#{LEGACY_YEAR}/",
      expression: legacy_expression,
      action: 'redirect',
      action_parameters: {
        from_value: {
          status_code: 301,
          target_url: { expression: %(concat("#{SITE}/#{LEGACY_YEAR}", http.request.uri.path)) },
          preserve_query_string: true
        }
      }
    }
  end

  def legacy_expression
    directories, files = legacy_entries
    exact_paths = (directories + files).map { |entry| %("/#{entry}") }
    [
      *directories.map { |entry| %(starts_with(http.request.uri.path, "/#{entry}/")) },
      %(http.request.uri.path in {#{exact_paths.join(' ')}})
    ].join(' or ')
  end

  # Top-level entries of the 2026 site: [directories, files].
  def legacy_entries
    legacy_dir = File.join(@root, 'dist', LEGACY_YEAR)
    Dir.children(legacy_dir).sort.partition { |entry| File.directory?(File.join(legacy_dir, entry)) }
  end
end

redirects = CloudflareRedirects.new(File.expand_path('..', __dir__))
if ARGV.include?('--apply')
  count = redirects.apply(
    token: ENV.fetch('CLOUDFLARE_API_TOKEN') { abort('CLOUDFLARE_API_TOKEN is not set') },
    zone: ENV.fetch('CLOUDFLARE_ZONE_ID') { abort('CLOUDFLARE_ZONE_ID is not set') }
  )
  puts "Replaced the Redirect Rules with #{count} rules."
elsif ARGV.include?('--json')
  puts JSON.pretty_generate(rules: redirects.rules)
else
  puts redirects.summary
end
