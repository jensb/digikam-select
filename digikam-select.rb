#!/usr/bin/ruby
# encoding: UTF-8
#
# Digikam-select. Script to select Digikam images by tag, rating or name,
# then copy or (sym)link them into another location.
#
# (c) Jens Benecke, 2017. Distributed under GPL3 license.
#
# Roadmap:
# v0.1  - Get files by (flat) tag name and copy to target dir. Keep album structure.
# v0.2  - Get files also by rating.
# v0.3  - Also allow symlinking or hardlinking (if kept on same device).
# v0.4  - Add ImageMagick convert options for JPG files.
# v0.5  - Add interactive mode and force mode.
# ...
# v1.0  - Add sync mode.
#

require 'progressbar'       # required for eye candy during conversion
require 'fileutils'         # required to move and link files around
require 'sqlite3'           # required to access iPhoto database
require 'optparse'          # required to parse options
require 'pp'

## I was going to require these but installing libmagickwand-dev on Ubuntu requires 29MB (!!!)
## of devel libraries just to be able to 'gem install rmagick'. NO thanks.
#require 'rmagick'           # to convert and recompress images
#include Magick

VERSION = 0.1
$debug = 0                  # global debugging setting

# Main part. Run after all function definitions at the end of the file.
def main
  options = get_options
  files = get_files(options)
  put_files(files, options)
end


# Check parameter validity and combinations, return help text and define options hash.
def get_options
# Set Defaults
  options = {}
  errors = nil

  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options]"

    # Operational details
    opts.on("-v", "--verbose", "Show detailed progress while working") do |v|
      options[:debug] = v ? 2 : 1
      $debug = options[:debug]
    end
    opts.on("-q", "--quiet", "Show no output while working") do |v|
      options[:debug] = v ? 0 : 1
      $debug = options[:debug]
    end
    opts.on("--interactive", "Ask before overwriting or deleting files") do |v|
      options[:interactive] = v || false
    end
    opts.on("-d", "--dry-run", "Pretend mode. Do not write any files.") do |v|
      options[:dryrun] = v || false
    end

    # Source and target
    opts.on("-iDBFILE", "--input=DBFILE", "Set input Digikam database (digikam4.db)") do |v|
      v = File.expand_path(v)
      unless File.exist?(v) and File.readable?(v)
        puts "input file '#{v}' is not accessible"
        errors = true
      end
      options[:inputdb] = v
    end
    opts.on("-oDIR", "--output=DIR", "Set output directory") do |v|
      v = File.expand_path(v)
      unless Dir.exist?(v) and File.writable?(v)
        puts "output directory #{v} is not writable"
        errors = true
      end
      options[:output] = v
    end
    # TODO
    #opts.on("-nSTR", "--naming=STR", "Set output filename format. Default: %n.",
    #        "%n=name, %r=rating, %t=tag, %d=timestamp") do |v|
    #  options[:naming] = v || nil
    #end
    opts.on("--no-albums", "Do not create album folders (default: yes)") do |v|
      options[:albums] = v
    end
    options[:albums] ||= true

    # Image transfer options
    opts.on("-mMODE", "--mode=MODE", "Transfer mode (*copy*/link/symlink/convert)") do |v|
      options[:mode] = v
      unless ["copy", "convert", "link", "symlink"].include?(v)
        puts "incorrect copy mode '#{options[:mode]}' (copy, convert, symlink, link)"
        errors = true
      end
    end
    options[:mode] ||= "copy"
    opts.on("-cOPTS", "--compress=OPTS", "Process images using imageMagick 'convert'",
            "Example: '-quality 80 -geometry 1920x1080'.",
            "Will set '--mode=convert' and skip non-JPG",
            "files. Requires 'convert' binary in PATH.") do |v|
      options[:compress] = v || false
      options[:mode] = "convert"
      options[:convert_bin] = `which convert`.chomp
      unless options[:convert_bin] and `#{options[:convert_bin]} --help`.match(/ImageMagick 6/)
        puts "Missing convert binary in PATH. Install ImageMagick binaries and retry."
        errors = true
      end
    end
    opts.on("-f", "--force", "Force overwriting existing images in target",
            " folder structure (default: skip)") do |v|
      options[:force] = v || false
    end
    opts.on("-s", "--sync", "Sync mode: keep files that would be created",
            "and delete files that wouldn't be created.",
            "Any options are only applied to new files.") do |v|
      options[:sync] = v || false
    end

    # Image selection options
    opts.on("-tTAGS", "--tags=x,y,z", "Match images with tags (exact",
            "string, comma separated). Hierarchical tags",
            "are not supported yet (flat name only).") do |v|
      options[:tags] = v || []
    end
    opts.on("-rN", "--minrating=N", "Match images with at least N stars") do |v|
      options[:minrating] = v || 0
    end
    opts.on("-aSTR", "--album=STR", "Match albums matching this (sub)string",
            "All matches are concatenated using 'AND'.") do |v|
      options[:albumstr] = v || nil
    end

    # Catch-alls
    opts.on_tail("-h", "--help", "Show this message") do
      puts opts
      exit
    end

    opts.on_tail("--version", "Show version number") do
      puts "#{$0}, version #{VERSION}, (c) Jens Benecke (<jens-github@spamfreemail.de>)."
      exit
    end

  end.parse!
  pp options
  exit if errors
  options
end

# Open DB file, read all required data and close DB file.
# Return hash
def get_files(options)
  debug 2,
  db = SQLite3::Database.new(options[:inputdb])
  db.results_as_hash = true  # gibt [{"modelId"=>1, "uuid"=>"SwX6W9...", "name"=>".."

  # construct SQL query
  sql = []
  sqlbase = "SELECT DISTINCT r.specificPath AS root, a.relativePath AS path, i.name AS name
    FROM Images i
    LEFT JOIN ImageTags it ON it.imageid = i.id
    LEFT JOIN ImageInformation ii ON ii.imageid = i.id
    LEFT JOIN Tags t ON it.tagid = t.id
    LEFT JOIN Albums a ON i.album = a.id
    LEFT JOIN AlbumRoots r ON albumRoot = r.id
    WHERE root != '' AND path != '' "

  sql << "( t.name IN ('#{options[:tags].join(",")}') )"     if options[:tags]
  sql << "( ii.rating >= #{options[:minrating]} )"           if options[:minrating]
  sql << "( a.relativePath LIKE '%#{options[:albumstr]}%' )" if options[:albumstr]
  sqlstr = sql.join(" AND ")                      # TODO: make configurable
  sqlstr = " AND #{sqlstr}" unless sqlstr.empty?

  head, *data = db.execute2("#{sqlbase} #{sqlstr}")
  debug 2, "Found #{data.size} matching images.", true
  data
end


# Check presence and writability of output dir
# TODO: Warn if files exist in output dir and neither --force nor --sync is specified.
def put_files(files, options)
  unless options[:albums]
    # TODO: warn about filename conflicts here if there are any
  end
  files.each do |file|   # Array of hashes
    debug 2, "- #{file.inspect}", true
    source = File.join(file["root"], file["path"] || "", file["name"])
    unless File.exist?(source) and File.readable?(source)
      debug 0, "ERROR: File #{source} is not readable or doesn't exist"
      next
    end

    target = File.join(options[:output], (options[:albums] ? file["path"] : ""), file["name"])
    debug 2, "  Overwriting #{target}", true if options[:force] and File.exists?(target)
    debug 2, "  #{options[:mode]} #{source}\t=> #{target}"

    unless options[:dryrun]
      if File.exists?(target)
        if options[:force]
          File.delete(target)
        else
          debug 1, "  Skipping #{source}, #{target} exists"
          next
        end
      end

      if options[:interactive]
        puts "- Press ENTER to continue to next file ..."
        gets
      end

      targetdir = File.dirname(target)
      FileUtils.mkdir_p(targetdir) if options[:albums] and !Dir.exists?(targetdir)

      case options[:mode]
        when "copy" then FileUtils.cp(source, target)
        when "symlink" then FileUtils.symlink(source, target)
        when "hardlink" then FileUtils.link(source, target)
        when "convert" then
          if source =~ /.JPE?G$/i
            system("#{options[:convert_bin]} '#{source}' #{options[:compress]} '#{target}'")
          else
            debug 1, "  Copying, not converting #{source}"
            FileUtils.cp(source, target)
          end
          #i = Image.new(source)
          #i.write(target)
      end
    end

  end
end



# Print debug output, if ENV['DEBUG'] is equal or greater to level passed as parameter.
# levels: 3: debug output,   all found metadata for each photo
#         2: verbose output, most found metadata for each photo
#         1: normal output,  one line with basic info for each photo
#   default: quiet output,   progressbar with percent complete for whole operation
def debug(min_level, str, newline=true)
  return unless min_level==0 or (e = $debug and e.to_i >= min_level)
  if newline ; puts str else print str end
end

# Run main part
main

