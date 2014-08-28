class FileTrack
  # we create a class to track information about files we visit
  # the point here is that we don't want to have actual Ruby file structures around because we may be
  # iterating over many files and don't want to have file hanles all over the place.

  attr_accessor :name
  attr_accessor :size
  attr_accessor :fullname

  def initialize(f, parent_dir)
    # not sure yet if we actaully need this
    @name = f
    @fullname = File.join(parent_dir, f)
    @size = 0
  end
  
end

class DirComparisonResult
  # DirComparison holds the results of comparing two directories of files
  # It can tell us four specific sets of information:
  #  1) what files are "missing" from the compared directory that are in the reference directory
  #  2) what files are existing in the compared directory that are not in the reference directory
  #  3) what files differ in size between the compared and reference directories
  #  4) what files differ in content between the compared and reference directories
  #
  # Note that DirComparisonResult does not actually do the comparison.  It simply is used to
  # accumulate results and can output them to the terminal.
  #
  # One open design question is whether DirComparisonResult should contain a "flattened"
  # set of results, or whether it represents only the comparison of two specific directories, without
  # recursing into children.  For now for simplicy's sake we will make this a flatttened accumulation
  # of results.  Later we will see if we can store recursive structures.
  # 

  def initialize
    @missing      = []  # files missing from this dir as compared to reference
    @extras       = []  # files in this dir but missing from reference
    @wrongsize    = []  # files whose size differs
    @wrongcontent = []  # files whose byte content does not match
    @log_messages = []  # keep track of any accumulated error issues
  end

  def push_missing(f)
    # f is a FileTrack object
    @missing << f
  end

  def push_extras(f)
    # f is a FileTrack object
    @extras << f
  end

  def push_wrongsize(f)
    # f is a FileTrack object
    @wrongsize << f
  end

  def push_wrongcontent(f)
    # f is a FileTrack object
    @wrongcontent << f
  end

  def log(message)
    @log_messages << message
  end

  def printdetails(coll, sub_head)
    # referenced collection to print out details for
    puts "Details (#{sub_head}): "
    coll.each { |f| puts "\t#{f.fullname}" }
    puts ""
  end
  
  def printlog(messages)
    # print set of messages accumulated in log array
    puts "\nLog messages:"
    messages.each { |m| puts "\t#{m}" }
    puts ""
  end

  def printresult
    # print to the console the comparison result.

    # first print out a summary, then provide details

    puts "Summary: "
    puts "\t#{@missing.length} files missing" unless @missing.length < 1
    puts "\t#{@extras.length} extra files" unless @extras.length < 1
    puts "\t#{@wrongsize.length} files of differing sizes" unless @wrongsize.length < 1
    puts "\t#{@wrongcontent.length} files of differing content" unless @wrongcontent.length < 1
    puts "\tNo differences!" if isempty?
    puts "" unless isempty?

    ## now print out details by iterating over the collections
    printdetails(@missing, "missing") unless @missing.length < 1
    printdetails(@extras, "extras") unless @extras.length < 1
    printdetails(@wrongsize, "differing sizes") unless @wrongsize.length < 1
    printdetails(@wrongcontent, "differing content") unless @wrongcontent.length < 1

    printlog(@log_messages) unless @log_messages.length < 1

  end
  
  def isempty?
    return (@missing.length + @extras.length + @wrongsize.length + @wrongcontent.length) < 1
  end

end

class Ycomp

  def initialize(path1=nil, path2=nil)
    #
    #
    #
    @path1 = path1
    @path2 = path2
    @dcr = DirComparisonResult.new
  end

  def process_dir_entries(entries, parent_dir, type_of_entry)
    entries.each { |file| process_entry(file, parent_dir, type_of_entry) }
  end

  def process_entry(file, parent_dir, type_of_entry)

    # special . and .. file names will not be processed
    return if file == "." || file == ".."
 
    # this file is an extra file relative to our source directory
    case type_of_entry
    when :extra
      @dcr.push_extras(FileTrack.new(file, parent_dir))
    when :missing
      @dcr.push_missing(FileTrack.new(file, parent_dir))
    end
    
    # if this file is also a directory, then all of the directory contents are also extras
    expanded_path = File.join(parent_dir, file)

    if File.directory?(expanded_path)
      process_dir_entries(Dir.entries(expanded_path), expanded_path, type_of_entry)

    end #unless
  end #def
  
  def flatdircompare(path1, path2)
    # this compares just the files within the directories specified by path1 and path2
    # this is not recursive
    # it only does the comparison of the files specifically in the two directories


    raise "Source directory does not exist" if !Dir.exists?(path1)
    raise "Reference directory does not exist" if !Dir.exists?(path2)
    
    # now we're ready to compare the directories
    # simplest approach seems to be to get the arrays from both directories
    # and do collection-level comparison
    # the question is whether this is efficient.
    # we will try it but have to figure out if for large directories it's better
    # to do things manually.
    dir1_entries = Dir.entries(path1).sort!
    dir2_entries = Dir.entries(path2).sort!
    
    # since both arrays are sorted, we should be able to run through from the reference directory
    
    # we pop each entry from the first dir and correspondingly pop from reference dir
    dir1_file = dir1_entries.shift
    dir2_file = dir2_entries.shift

    while (dir1_file && dir2_file) do    
      case dir1_file <=> dir2_file
      when -1
        # if the popped entry in the source dir is < than the entry in the reference, this means
        # that our directory has an entra file.
        process_entry(dir1_file, path1, :extra)

        # and we pop the next file from our source dir
        dir1_file = dir1_entries.shift

      when 1
        # if the popped entry in the source dir > then entry in the reference dir, this means that the dir2 file
        # is MISSING the file in the source dir.
        process_entry(dir2_file, path2, :missing)

        # and we pop the next file from our reference dir
        dir2_file = dir2_entries.shift
      else
        # they are in both directories.  

        # so now we have to compare sizes and content
        file1_name = File.expand_path(dir1_file, path1)
        file2_name = File.expand_path(dir2_file, path2)

        f1_stat = File::Stat.new(file1_name)
        f2_stat = File::Stat.new(file2_name)

        if !f1_stat
          @dcr.log "Could not stat file #{file1_name}"
        elsif !f2_stat
          @dcr.log "Could not stat file #{file2_name}"
        else
          # we could stat both files, so now check their sizes
          @dcr.push_wrongsize(FileTrack.new(dir1_file, path1)) if f1_stat.size != f2_stat.size

          # sizes are the same so here is where we would be checking for byte by byte content

          ### TO IMPLEMENT
        end
        
        # Great, we move on and need to pop from both again
        dir1_file = dir1_entries.shift
        dir2_file = dir2_entries.shift
      end # case
    end # while

    # When we are at this point, dir1_file or dir2_file may individually be non-nil
    # so we must process each
    process_entry(dir1_file, path1, :extra) if dir1_file
    process_entry(dir2_file, path2, :missing) if dir2_file

    # now at this point one or both of the arrays are empty
    # depending on which array still has elements, we add to the missing or extras
    process_dir_entries(dir1_entries, path1, :extra)
    process_dir_entries(dir2_entries, path2, :missing)

  end

  def compare()
    #
    # Compare path1 (our dir of interest) to path2 (our "reference" directory)
    flatdircompare(@path1, @path2)

    @dcr.printresult

  end

end

def testpoint(message,dir1,dir2)
  begin
    puts "-" * 20
    puts message
    yc = Ycomp.new(dir1, dir2)
    yc.compare
  rescue => detail
    puts "\t\t** Exception: #{detail}"
  end
end

def tester
#  df = DirComparisonResult.new
#  df.printresult

#  puts "---"
#  ff = FileTrack.new
#  ff.name = "aa"
#  df.push_wrongsize ff
#  df.printresult

#  ff = FileTrack.new
#  ff.name = "bb1"
#  df.push_missing ff

#  ff = FileTrack.new
#  ff.name = "bb2"
#  df.push_missing ff

#  ff = FileTrack.new
#  ff.name = "bb3"
#  df.push_missing ff

#  df.printresult

  testpoint("Non-existed src and reference dirs", "./none_test1", "./none_test2")
  testpoint("Non-existed src dir", "./none_test1", "./test2")
  testpoint("Non-existed reference dir", "./test1", "./none_test2")
  testpoint("Empty src and reference dirs", "./test1", "./test2")
  testpoint("Empty src and non-empty reference dirs", "./test1", "./test2b")
  testpoint("Non-Empty src and empty reference dirs", "./test1b", "./test2")
  testpoint("test B-1 (expect missing file)", "./test1b", "./test2b")
  testpoint("test B-2 (expect extra file)", "./test2b", "./test1b")
  testpoint("test C: (expect size diff)", "./test1c", "./test2c")

  testpoint("test D-1: (expect extra files with subdir)", "./test1d", "./test2d")
  testpoint("test D-2: (expect missing files with subdir)", "./test2d", "./test1d")

end
