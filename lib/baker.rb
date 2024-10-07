# frozen_string_literal: true

require_relative "baker/version"

# stdlib
require 'optparse'
require 'tempfile'
require 'fileutils'
require 'ostruct'

# gems
require 'rails/generators'
require 'vtparser'
require "tty-prompt"
require 'rainbow/refinement' # for string colors 
using Rainbow

require_relative 'baker/bakerlib'
require_relative 'baker/bakeractions'

class Baker

  include BakerActions

  attr_accessor :debug, :recipe, :file_name, :interactive
  def inspect
    # Nothing gained here from seeing instance variables
    return to_s
  end

  def to_hash
    (self.instance_variables - [:@file_contents, :@recipe]).inject({}){ |cont, attr| cont[attr] = instance_variable_get(attr); cont }
  end

  def process_args

    begin
      OptionParser.new do |opts|
        opts.banner = 'Usage: baker [options] [file]'

        opts.on('-v', '--verbose', 'Enable verbose/debug output') do
          @debug = true
          puts "Verbose mode enabled".yellow
        end

        opts.on('-d', '--diff', 'Show diff of the bake file to its template') do
          @diff_mode = true
          puts "Diff mode enabled".yellow if $stdout.tty?
        end

        opts.on('-i', '--interactive', 'Enable interactive mode') do
          @interactive = true
        end

        opts.on('-h', '--help', 'Displays Help') do
          puts opts
          exit
        end
      end.parse!
    rescue OptionParser::InvalidOption => e
      puts e
      exit(1)
    end

    @file_name = ARGV.shift || 'template.md'
    @file_name = File.expand_path(@file_name)

    if !File.exist?(@file_name)
      puts "Error: File #{@file_name} does not exist.".red
      exit(1)
    end

    @original_dir = Dir.pwd

    puts "Bake File: #{@file_name}".yellow if @debug

    return nil
  end

  def expand_vars(input)

    return "" if input.nil? || input.empty?

    # Check if we received a ruby string literal, otherwise wrap it in %()
    require 'ripper'
    if Ripper.sexp(input)&.dig(1,0,0) != :string_literal
      input = '%(' + input + ')'
    end

    o = OpenStruct.new(@context)
    o.singleton_class.define_singleton_method(:const_missing) { |name| o[name] }
    
    return o.instance_eval(input)
  end

  # Run diff will unmark all completed steps and perform a diff against the original template source
  #
  # The original template source is searched using the ::template_source directive.
  #
  # The diff is shown using git diff.
  def run_diff

    template_source_file = nil

    @recipe.steps.each { |line|      
      case line.type
      when :directive
        case line.directive_type
        when :template_source
          template_source_file = line.content
        end
      when :ruby, :shell, :manual
        line.mark_todo if line.completed?
      end
    }

    if template_source_file.nil?
      puts "Error: No template source file found. Please add a ::template_source{path_to_template} directive to the bake file.".red
      exit(1)
    end
    
    to_write = @recipe.to_s
    Tempfile.open("#{File.basename(@file_name)}_unbaked") do |tempfile|
      tempfile.write(to_write)
      tempfile.flush
      # If attached to a tty, show color diff/word diff
      puts `git diff #{"--word-diff --color" if $stdout.tty?} #{template_source_file} #{tempfile.path}`
    end
  end

  def run_safe

    run
  
  rescue SystemExit
    # fall through
  rescue Exception => e
    puts 
    puts e.full_message(highlight: true, order: :bottom)

    puts
    require 'pathname'
    puts " → Please fix the error and run `baker #{Pathname.new(@file_name).relative_path_from(@original_dir) }` to continue.".yellow
  end

  def run

    status = process_args
    return if status == :close

    # @file_contents represents the file that baker believes is on disk. 
    # It is used to check if there was any concurrent modification.
    @file_contents = File.read(@file_name)
    
    @recipe = Recipe.from_s(@file_contents)

    if @diff_mode
      run_diff()

      return
    end
    
    @context = { file_name: @file_name }
  
    @recipe.steps.each { |line|
      
      if @debug
        puts "#{line.type} : #{line}"
      else
        puts line
      end

      case line.type

      when :directive
        case line.directive_type
        when :var

          # STDERR.puts line.inspect
          if line.attributes == nil || line.attributes.strip.start_with?(/default\s*=/)
            puts ""

            initial_value = expand_vars((line.attributes || "").sub(/^\s*default\s*=\s*/, ''))

            puts initial_value

            use_tty = true
            if use_tty
              line.attributes = TTY::Prompt.new.ask(" → Please enter your value for variable '#{line.content}':\n".yellow, value: initial_value)
            else
              puts " → Please enter your value for variable '#{line.content}':".yellow
              line.attributes = STDIN.gets().strip
            end
            line.lines = ["::var[#{line.content}]{#{line.attributes}}\n"]
            @context[line.content] = line.attributes

            puts ""
          else
            @context[line.content] = line.attributes
            puts " → Variable '#{line.content}' set to '#{line.attributes}'.".yellow
            puts ""
          end

          next

        when :cd
          o = OpenStruct.new(@context)
          o.singleton_class.define_singleton_method(:const_missing) { |name| o[name] }
          
          dir = o.instance_eval(line.content)
          puts " → Changing directory to: #{dir}".yellow

          Dir.chdir(dir)

        when :template          

          o = OpenStruct.new(@context)
          o.singleton_class.define_singleton_method(:const_missing) { |name| o[name] }

          template_name_suggestion = o.instance_eval(line.content) || File.filename(@file_name)
          
          puts (" → Executing template directive. Creating file: " + template_name_suggestion).yellow

          template_name_suggestion = File.expand_path(template_name_suggestion)
          if File.exist?(template_name_suggestion)
            puts "Error: The file #{template_name_suggestion} already exists.".red

            puts " ? Do you want to overwrite the file? Enter y/Y to overwrite. Any other key to cancel and exit baker.".yellow
            
            # Make a copy of the file contents before the user decides to overwrite
            @file_contents = File.read(template_name_suggestion)

            exit(1) if STDIN.gets().strip.downcase != 'y'
          end
          line.lines = ["::template_source[#{@file_name}]"]

          puts ""

          @file_name = template_name_suggestion
          save
          next
        when :template_source
          # Do nothing
        else
          raise "Unknown directive type: #{line.directive_type}"
        end
        next
      when :nop
        # Do nothing
        next

      when :ruby
        #eval line.content

        if line.completed?
          puts "  → Already completed".green if @debug
          next
        end
        @context[:rails_gen_base] = Rails::Generators::Base.new
        @context[:myself] = self
        o = Struct.new(*@context.keys).new(*@context.values)
        # require 'ostruct'
        # o = OpenStruct.new(@context)
        o.singleton_class.define_singleton_method(:const_missing) { |name| o[name] }
        o.define_singleton_method (:inspect) {
            "<#{self.class}: #{self.instance_variables.map{|v| "#{v}=#{instance_variable_get(v).inspect.truncate(100)}"}.join(", ")}>"
        }

        o.extend Forwardable
        o.def_delegators :rails_gen_base, :create_file, :copy_file, :inside, :environment, :gem, :generate, :git, :initializer, :lib, :rails_command, :rake, :route
        o.def_delegators :myself, :inject_into_file, :append_file, :append_to_file, :insert_into_file, :gsub_file

        #o.singleton_class.include(Thor::Actions)
        #o.singleton_class.include(Rails::Generators::Actions)
        #o.destination_root = Dir.pwd
        
        command = line.command

        # Apply indentation and any additional formatting
        to_display = unindent_common_whitespace(format_command(command, max_line_length = 160))
        line_will_break = to_display =~ /\n/ || to_display.length > 80
        to_display = "\n#{to_display}\n" if line_will_break && to_display.scan(/\n/).length == 0
        to_display = to_display.indent(1).gsub(/^/, '▐').indent(3) if line_will_break     
        puts (" → Executing ruby code: #{"\n" if line_will_break}#{to_display}").yellow

        begin
          result = o.instance_eval(command)
        rescue Exception => e
          result = e
        end

        if result == false
          # We assume the ruby command outputted an error message
          puts "  → Please fix the error or mark the todo as done.".red          
          puts "      #{@file_name}:#{line.line_index}".red
          exit 1
        end

        if result.is_a?(Exception)
          puts "  → Failed with error:".red
          puts result
          puts result.backtrace
          puts "  → Please fix the error or mark the todo as done.".red
          puts "      #{@file_name}:#{line.line_index}".red
          exit 1
        end        
      
        puts "  → Successfully executed".green
        puts
        line.mark_complete
      
      when :shell
        # system line.content

        if line.completed?
          next
        end
        require 'ostruct'
        o = OpenStruct.new(@context)
        o.singleton_class.define_singleton_method(:const_missing) { |name| o[name] }

        command = o.instance_eval("%(" + line.command + ")")

        # Apply indentation and any additional formatting
        to_display = format_command(command, max_line_length = 160)
        line_will_break = to_display =~ /\n/ || to_display.length > 80
        to_display = "\n#{to_display}\n" if line_will_break && to_display.scan(/\n/).length == 1
        to_display = to_display.indent(1).gsub(/^/, '▐').indent(3) if line_will_break     
        puts (" → Executing shell command: #{"\n" if line_will_break}#{to_display}").yellow
        
        mode = :ptyspawn_with_parser
        
        case mode
          
        when :system
          puts ">>>>>>".white
          # Bundler.with_clean_env {
          result = system(command, out: STDOUT)
          #}
          puts ">>>>>>".white

        when :open3 
          
          exit_status = nil
          require 'open3'
          Open3.popen2e(command) do |stdin, stdout_and_stderr, wait_thr|
            stdout_and_stderr.each_line do |line|
              # Remove trailing whitespace and apply formatting
              formatted_line = line.rstrip.indent(2).gsub(/^/, '▐').indent(3)
              puts formatted_line
            end
            exit_status = wait_thr.value
          end
          result = exit_status&.success?

        when :ptyspawn_with_parser

          require 'pty'
          begin

            line_indent = '   ▐  '
            line_indent_width = line_indent.length
            line_indent = line_indent.yellow
            first_line_indent = true

            parser = VTParser.new do |action, ch, n, a|
              print line_indent if first_line_indent
              first_line_indent = false

              to_output = VTParser.to_ansi(action, ch, n, a)

              case action
              when :print, :execute, :put, :osc_put
                if ch == "\n" || ch == "\r"
                  print ch
                  print line_indent
                  next
                end
              when :csi_dispatch
                if to_output == "\e[2K"
                  print "\e[2K"
                  print line_indent
                  next
                else
                  if ch == 'G'
                    # puts "to_output: #{to_output.inspect} action: #{action} ch: #{ch.inspect}"
                    # && parser.params.size == 1
                    print "\e[#{parser.params[0] + line_indent_width}G"

                    next
                  end
                end
              end

              print to_output
            end

            PTY.spawn(command) do |stdout_and_stderr, stdin, pid|

              thread = Thread.new do
                STDIN.timeout = 0.1
                while pid != nil
                  begin
                    stdin.write(STDIN.read(1024))
                  rescue IO::TimeoutError
                    # No input / repeat
                  end
                end
                STDIN.timeout = nil
              end

              begin
                stdout_and_stderr.winsize = [$stdout.winsize.first, $stderr.winsize.last - line_indent_width]

                stdout_and_stderr.each_char do |char|

                  parser.parse(char)

                end
              rescue Errno::EIO
                # End of output
              end
              Process.wait(pid)
              pid = nil # Signal to the input thread to exit
              thread.join
              exit_status = $?.exitstatus
              result = exit_status == 0

              # Clear the line, reset the cursor to the start of the line
              print "\e[2K\e[1G"
              
            end
          rescue PTY::ChildExited
            # Child process has exited
            result = true
          end
        end

        puts ""

        if result
          puts "  → Successfully executed".green
          puts
          line.mark_complete
        else
          error = $?.to_s

          if error.length < 80 && !(error =~ /\n/)
            puts "  → Failed with error: #{error}".red
          else            
            puts "  → Failed with error:".red
            to_display = format_command(error, max_line_length = 160)
            to_display = "\n#{to_display}\n " if to_display.scan(/\n/).length == 0
            to_display = to_display.indent(1).gsub(/^/, '▐').indent(3)  
            puts to_display.red
          end
          puts "  → Please fix the error or mark the todo as done:".red
          puts "      #{@file_name}:#{line.line_index}".red
          exit 1
        end

      when :manual

        if line.completed?
          next
        end

        puts " → Perform the following steps manually:".yellow
        puts line.description

        puts
        puts " → Please enter: y/Y/x/./<space> to mark complete and continue or any other key to do nothing and exit".yellow
        input = STDIN.gets()

        case input.strip.downcase
        when 'y', 'x', '.', ' '
          line.mark_complete
        else
          puts "  → Please complete the task manually and run baker again".red
          puts "      #{@file_name}:#{line.line_index}".red
          exit 1
        end
      end

      save
    }

    puts " → All steps completed.".green

  end

  def save
    
    to_write = @recipe.to_s

    if File.exist?(@file_name) && @file_contents != nil
      if File.read(@file_name) != @file_contents
        puts " → File has been modified by another program, while baker processed todos.".red

        while true
          puts " ? Do you want to overwrite the file? Enter y/Y to overwrite or d/D to show diff. Any other key to cancel and exit baker.".yellow
          input = STDIN.gets()
          case input.strip.downcase
          when 'y'
            puts " → Exiting without saving. Please manually mark the successfully executed steps as done.".red
            exit 1
          when 'd'            
            puts " → Diff:".red
            Tempfile.open('assumed_file_contents') do |tempfile|
              tempfile.write(@file_contents)
              tempfile.flush
              puts `git diff --color #{tempfile.path} #{@file_name}`
            end
            puts
            next # Repeat
          end          
          break
        end
      end
    end

    if !File.exist?(@file_name) || File.read(@file_name) != to_write
      File.write(@file_name, to_write)
      @file_contents = to_write
    else
      puts " → No changes to save.".yellow
    end

  end    

end

if __FILE__==$0
  Baker.new.run_safe
end