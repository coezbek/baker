require 'rainbow/refinement'
using Rainbow

module BakerActions

  # Perform substitution (once!) in a file
  def sub_file(destination_file_name, regex, *args, &block)

    content = File.read(destination_file_name)

    success = content.sub!(regex, *args, &block)

    if success
      File.open(destination_file_name, "wb") { |file| file.write(content) }
      puts "sub_file successfully performed for #{destination_file_name}".green
      return true
    else
      puts "Match not found!".red
      return false
    end
  rescue Errno::ENOENT
    puts "The file #{destination_file_name} does not exist".red
    return false
  end

  def gsub_file(destination_file_name, regex, *args, &block)

    content = File.read(destination_file_name)

    success = content.gsub!(regex, *args, &block)

    if success
      File.open(destination_file_name, "wb") { |file| file.write(content) }
      puts "gsub_file successfully performed for #{destination_file_name}".green
      return true
    else
      puts "Match not found!".red
      return false
    end
  rescue Errno::ENOENT
    puts "The file #{destination_file_name} does not exist".red
    return false
  end

  #
  # Returns the login-user for the given host or nil if none is defined in ~/.ssh/config
  #
  def user_for_host(host)
    require 'net/ssh/config'
    Net::SSH::Config.for(host)[:user]
  end

  def rails_run(command, environment: nil)

    Tempfile.open(["rails_run", '.rb']) do |tempfile|
      tempfile.write(command)
      tempfile.flush

      result = pty_spawn(%Q(rails runner #{tempfile.path} -w #{environment ? "--environment #{environment}" : ""}))

      return result == 0
    end

  end

  # Injects content (given either as second parameter or block) into destination file
  # at the position specified by a regex as either :before or :after.
  #
  # The data to be inserted may be given as a block, but the block isn't passed further down to gsub, but evaluated eagerly.
  #
  def inject_into_file(destination_file_name, *args, &block)
    
    begin
      to_insert = block_given? ? block : args.shift
      to_insert = to_insert.is_a?(Proc) ? to_insert.call : to_insert

      config = args.shift || {}

      # Assume :after end if no config is given
      config[:after] = /\z/ unless config.key?(:before) || config.key?(:after)

      regex = config[:before] || config[:after]
      regex = Regexp.escape(regex) unless regex.is_a?(Regexp)

      # Read the content of the file
      content = File.read(destination_file_name)
      
      replacement = if config.key?(:after)
        '\0' + to_insert
      else
        to_insert + '\0'
      end

      if config[:once]
        success = content.sub!(/#{regex}/, replacement)
      else
        success = content.gsub!(/#{regex}/, replacement)
      end

      # If gsub! was successful (i.e., flag was found and content replaced)
      if success
        File.open(destination_file_name, "wb") { |file| file.write(content) }
        puts "Content successfully inserted into #{destination_file_name}".green
        return true
      else
        if content.include?(to_insert)
          puts "Match not found, but content already exists in #{destination_file_name}. Please review and manually confirm.".blue
          return false
        else
          puts "Match not found!".red
          return false
        end
      end

    rescue Errno::ENOENT
      puts "The file #{destination_file_name} does not exist".red
      return false
    rescue => e
      puts "An error occurred: #{e.message}".red
      return false
    end
  end
  alias_method :insert_into_file, :inject_into_file

  # Append text to end of file
  #
  # ==== Parameters
  # path<String>:: path of the file to be changed
  # data<String>:: the data to append to the file, can be also given as a block.
  #
  # ==== Example
  #
  #   append_to_file 'config/environments/test.rb', 'config.gem "rspec"'
  #
  #   append_to_file 'config/environments/test.rb' do
  #     'config.gem "rspec"'
  #   end
  #
  def append_to_file(path, *args, &block)
    config = args.last.is_a?(Hash) ? args.pop : {}
    config[:before] = /\z/
    insert_into_file(path, *(args << config), &block)
  end
  alias_method :append_file, :append_to_file

  def unindent_common_whitespace(string)
    common_whitespace = " " * (string.scan(/^[ ]+/).map { |s| s.length }.min || 0)
    string.gsub(/^#{common_whitespace}/, "")
  end

  #
  # Rebreak given string to fit within max_line_length for display purposes
  # 
  def format_command(command, max_line_length)
    lines = command.split("\n")
    formatted_lines = []

    lines.each do |line|
      position = 0
      line_length = line.length

      starting_indent = line[/\A\s*/]

      current_line = ''
      while position < line_length
        last_break_position = nil
        start_position = position

        while position < line_length && current_line.length < max_line_length
          char = line[position]
          current_line += char

          # Check for acceptable break positions
          if [' ', "\t", '{', '}', '(', ')', '[', ']', '.', ',', ';', ':'].include?(char)
            last_break_position = position
          end

          position += 1
        end

        if position < line_length
          # Line is too long, need to break
          if last_break_position && last_break_position >= start_position
            # Break at last acceptable position
            break_position = last_break_position + 1  # Include the break character
            current_line = line[start_position...break_position]
            position = break_position
          else
            # No acceptable break position, break at max_line_length
            current_line = line[start_position...position]
          end
          # Add right-aligned '\' to indicate continuation
          current_line = current_line.ljust(max_line_length - 1) + '\\'
        end

        formatted_lines << current_line
        current_line = starting_indent
      end
    end

    formatted_lines.join("\n")
  end

  # Spawn a PTY and run the given command
  def pty_spawn(command)
    require 'pty'

    begin
      PTY.spawn(command) do |stdout_and_stderr, stdin, pid|

        # Input Thread
        input_thread = Thread.new do

          STDIN.raw do |io|
            loop do
              break if pid.nil?
              begin
                if io.wait_readable(0.1)
                  data = io.read_nonblock(1024)
                  stdin.write data
                end
              rescue IO::WaitReadable
                # No input available right now
              rescue EOFError
                break
              rescue Errno::EIO
                break
              end
            end
          end
        end

        # Pipe stdout and stderr to the parser
        begin

          begin
            winsize = $stdout.winsize
          rescue Errno::ENOTTY
            winsize = [0, 120] # Default to 120 columns
          end
          # Ensure the child process has the proper window size, because 
          #  - tools such as yarn use it to identify tty mode
          #  - some tools use it to determine the width of the terminal for formatting
          stdout_and_stderr.winsize = winsize
          
          stdout_and_stderr.each_char do |char|

            print char

          end
        rescue Errno::EIO
          # End of output
        end

        # Wait for the child process to exit
        Process.wait(pid)
        pid = nil
        input_thread.join
        return exit_status = $?.exitstatus
      end

    rescue PTY::ChildExited => e
      puts "The child process exited: #{e}"
      return 1
    end
  end

end
