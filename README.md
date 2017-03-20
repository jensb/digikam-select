# digikam-select

Digikam is a great DAM (Digital Asset Management) application and image editor.
This script adds some non-gui (= cron capable) batch export features to Digikam.

## Requirements

digikam-select is a Ruby application and so needs a Ruby interpreter. (v2.2 will do fine)
In addition, the following Ruby gems are required.

    require 'progressbar'       # required for eye candy during conversion
    require 'fileutils'         # required to move and link files around
    require 'sqlite3'           # required to access iPhoto database
    require 'optparse'          # required to parse options
    require 'pp'

They can be installed using these commands e.g. on Ubuntu 16.04:

    $ sudo apt-get install ruby2.2 ruby2.2-dev libsqlite3-dev
    $ sudo gem2.2 install sqlite3 progressbar

But any newer Ruby version should also do if already installed.

## Usage

    $ ruby digikam-select.rb --help
    Usage: digikam-select.rb [options]
    -v, --verbose         Show detailed progress while working
    -q, --quiet           Show no output while working
        --interactive     Ask before overwriting or deleting files
    -d, --dry-run         Pretend mode. Do not write any files.
    -i, --input=DBFILE    Set input Digikam database (digikam4.db)
    -o, --output=DIR      Set output directory
        --no-albums       Do not create album folders (default: yes)
    -m, --mode=MODE       Transfer mode (*copy*/link/symlink/convert)
    -c, --compress=OPTS   Process images using imageMagick 'convert'
                          Example: '-quality 80 -geometry 1920x1080'.
                          Will set '--mode=convert' and skip non-JPG
                          files. Requires 'convert' binary in PATH.
    -f, --force           Force overwriting existing images in target
                           folder structure (default: skip)
    -t, --tags=x,y,z      Match images with any listed tag (exact
                          string match). Hierarchical tags are
                           not supported yet (flat name only).
    -r, --minrating=N     Match images with at least N stars
    -a, --album=STR       Match albums matching this (sub)string
                          All matches are concatenated using 'AND'.
    -h, --help            Show this message
        --version         Show version number

## Examples

Export all images with rating 3 or better:

    $ ruby digikam-export.rb -i ~/Pictures/digikam4.db -o ~/image_export -r3
    
Export all images tagged "Funny" or "Sad":

    $ ruby digikam-export.rb -i ~/Pictures/digikam4.db -o ~/image_export -t Funny,Sad
    
Export all images in Albums matching "Tour":

    $ ruby digikam-export.rb -i ~/Pictures/digikam4.db -o ~/image_export -a Tour
    
Export, and convert to 50% dimensions:

    $ ruby digikam-export.rb -i ~/Pictures/digikam4.db -o ~/image_export -c "-geometry 50%"
    

## License
The license of this script is GPL3 as of now. If this causes problems with your intended usage please contact me.

## Contact
Contact me at jens-github@spamfreemail.de or via Github.
