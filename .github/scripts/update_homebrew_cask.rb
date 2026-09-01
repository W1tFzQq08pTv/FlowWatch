require "digest"

if ARGV.length < 3
  warn "Usage: update_homebrew_cask.rb <dmg-path> <version> <cask-path>"
  exit 2
end

dmg_path = ARGV[0]
version = ARGV[1]
cask_path = ARGV[2]

sha256 = Digest::SHA256.file(dmg_path).hexdigest

data = File.read(cask_path)

data = data.gsub(/version\s+"[^"]+"/, "version \"#{version}\"")
data = data.gsub(/sha256\s+"[^"]+"/, "sha256 \"#{sha256}\"")
data = data.gsub(
  /url\s+"https:\/\/github\.com\/W1tFzQq08pTv\/FlowWatch\/releases\/download\/v#\{version\}\/FlowWatch(?:-#\{version\})?\.dmg"/,
  'url "https://github.com/W1tFzQq08pTv/FlowWatch/releases/download/v#{version}/FlowWatch.dmg"'
)

unless data.match?(/^  auto_updates true$/)
  homepage_pattern = /^  homepage "[^"]+"$/
  raise "Unable to find homepage stanza in #{cask_path}" unless data.match?(homepage_pattern)

  data = data.sub(homepage_pattern) { |line| "#{line}\n  auto_updates true" }
end

File.write(cask_path, data)

puts "Updated #{cask_path} to version #{version}"
puts "sha256 #{sha256}"
