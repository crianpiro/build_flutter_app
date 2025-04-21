require 'optparse'

options = {
  type: "-patch",
  version: ""
}

OptionParser.new do |opts|
  opts.banner = "Usage: update_version.rb [options]"

  # Define a flag (--verbose)
  opts.on('-t', '--type', 'Update version number according to type (major, minor, patch)') do |option|
    options[:type] = option
  end

  # Define a help option
  opts.on('-h', '--help', 'Show this help message') do
    puts opts
    exit
  end
end.parse!

pubspec_path = File.expand_path('../pubspec.yaml', __FILE__)

# Read the file into an array of lines
lines = File.readlines(pubspec_path)

# Find the line containing the version and update it
lines.map! do |line|
  if line.strip.start_with?('version:') && line =~ /(\d+)\.(\d+)\.(\d+)\+(\d+)/
      major, minor, patch, build = $1.to_i, $2.to_i, $3.to_i, $4.to_i
      
      case options[:type] 
      when 'major'
        major += 1
        minor = 1
        patch = 0
      when 'minor'
        minor += 1
        patch = 0
      else
        patch += 1
      end

      build += 1
      line = "version: #{major}.#{minor}.#{patch}+#{build}\n"
      puts "#{major}.#{minor}.#{patch}+#{build}"
  end
  line
end

# Write the updated lines back to the file
File.open(pubspec_path, 'w') { |file| file.puts(lines) }