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
require_relative 'baker/plugins'
require_relative 'baker/baker_config'

class Baker
  include BakerActions

  class << self
    # sig {returns(Plugins)}
    def plugin
      @plugin ||= Plugins.new
    end
    alias_method :plugins, :plugin
  end

  attr_accessor :debug, :recipe, :file_name, :interactive

  # Options Parser
  attr_accessor :opts

  def inspect
    # Nothing gained here from seeing instance variables
    return to_s
  end

  def to_hash
    (self.instance_variables - [:@file_contents, :@recipe]).inject({}){ |cont, attr| cont[attr] = instance_variable_get(attr); cont }
  end

  def create_options_parser

    @opts = OptionParser.new

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

    opts.on('-f', '--fast-forward', 'Skip all completed steps') do
      @fast_forward = true
    end

    opts.on('--no-save', 'Do not save any changes to the bake file') do
      @no_save = true
    end

    opts.on('-h', '--help', 'Displays Help') do
      puts opts
      exit
    end
  end

  def process_args
    run_plugins(:before_options)
    
    begin
      opts.parse!
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

    run_plugins(:after_options)
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

  def load_file

    @context = { file_name: @file_name }

    case Baker.plugins.run(:before_load, baker: self, context: @context)
    when :ask
      puts " ? Press y/Y to continue. Any other key to cancel and exit baker.".yellow
      exit(1) if prompt_user_choice(nil) == :abort
    end # Fallthrough: :continue, :skip

    # @file_contents represents the file that baker believes is on disk.
    # It is used to check if there was any concurrent modification.
    @file_contents = File.read(@file_name)

    @recipe = Recipe.from_s(@file_contents)

    case Baker.plugins.run(:after_load, baker: self, context: @context)
    when :ask
      puts " ? Press y/Y to continue. Any other key to cancel and exit baker.".yellow
      exit(1) if prompt_user_choice(nil) == :abort
    end # Fallthrough: :continue, :skip

  end

  def load_config
    Dir.mkdir(File.expand_path('~/.baker')) unless Dir.exist?(File.expand_path('~/.baker'))
    @config = BakerConfig.new(File.expand_path('~/.baker/config.yml'))
  end

  def run

    load_config

    create_options_parser

    Baker.plugins.init

    process_args

    load_file

    if @diff_mode
      run_diff()

      return
    end

    # Skip stack is used to maintain a list of indentation levels that we need to skip
    @skip_stack = []

    @recipe.steps.each_with_index do |line, index|

      # Skip all completed (incl. strikethrough) steps in fast forward mode
      if line.type != :directive
        if @fast_forward && line.completed?
          next
        end
        @fast_forward = false
      end

      if @debug
        puts "#{line.type} : #{line}"
      else
        puts line
      end

      # Check if we need to skip this line due to skip stack
      if !@skip_stack.empty?
        current_skip_indent = @skip_stack.last

        current_line_indent = line.indentation_level
        if current_line_indent == nil || current_line_indent > current_skip_indent
          # Skip this line
          next
        else
          # We are back to a lower indentation, pop the skip stack
          @skip_stack.pop
        end
      end

      case line.type

      when :directive
        case line.directive_type
        when :var

          # STDERR.puts line.inspect
          if line.attributes == nil || line.attributes.strip.start_with?(/default\s*=/)
            puts ""

            initial_value = expand_vars((line.attributes || "").sub(/^\s*default\s*=\s*/, ''))

            raise "Initial value couldn't be determined for variable '#{line.content}'" if initial_value.nil?

            use_tty = true
            if use_tty
              prompt = TTY::Prompt.new

              history = @config[:history, line.content.to_sym] || []

              history.each { |h| prompt.reader.add_to_history(h) }

              line.attributes = prompt.ask(" → Please enter your value for variable '#{line.content}':\n".yellow, value: initial_value)

              history << line.attributes

              @config[:history, line.content.to_sym] = history.uniq
              @config.flush

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

          if @interactive
            puts " ? About to execute template directive. Press y/Y to continue. Any other key to cancel and exit baker.".yellow
            puts " ? Press y/Y to continue. Any other key to cancel and exit baker.".yellow

            exit(1) if prompt_user_choice(line) == :abort
          end

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

        o.singleton_class.define_singleton_method(:const_missing) { |name| o[name] }
        o.define_singleton_method (:inspect) {
            "<#{self.class}: #{self.instance_variables.map{|v| "#{v}=#{instance_variable_get(v).inspect.truncate(100)}"}.join(", ")}>"
        }

        o.extend Forwardable
        o.def_delegators :rails_gen_base, :template, :inject_into_class, :create_file, :copy_file, :inside, :environment, :gem, :generate, :git, :initializer, :lib, :rails_command, :rake, :route
        o.def_delegators :myself, *BakerActions.instance_methods(false)

        command = line.command

        # Apply indentation and any additional formatting
        to_display = unindent_common_whitespace(format_command(command, max_line_length = 160))
        line_will_break = to_display =~ /\n/ || to_display.length > 80
        to_display = "\n#{to_display}\n" if line_will_break && to_display.scan(/\n/).length == 0

        # Replace all trailing whitespace with ·
        to_display = to_display.gsub(/\s(?=\s*$)/, '·')

        to_display = to_display.indent(1).gsub(/^/, '▐').indent(3) if line_will_break

        if @interactive
          puts " → About to execute ruby code: #{"\n" if line_will_break}#{to_display}".yellow
        end

        asked_before = false
        case Baker.plugins.run(:before_execution, line: line, baker: self, command: command, context: @context)
        when :skip
          next
        when :ask
          puts " ? Press y/Y to continue. Any other key to cancel and exit baker.".yellow
          exit(1) if prompt_user_choice(line) == :abort
          asked_before = true
        end # Fallthrough: :continue

        if @interactive && !asked_before
          puts " ? Press y/Y to continue. Any other key to cancel and exit baker.".yellow

          exit(1) if prompt_user_choice(line) == :abort
        end

        puts (" → Executing ruby code: #{"\n" if line_will_break}#{to_display}").yellow

        begin
          if @file_name
            result = o.instance_eval(command, @file_name, line.source_code_line_index)
          else
            result = o.instance_eval(command)
          end
        rescue Exception => e
          result = e
        end

        if result == false
          # We assume the ruby command outputted an error message
          puts "  → Please fix the error or mark the todo as done.".red
          puts "      #{@file_name}:#{line.source_code_line_index}".red
          exit 1
        end

        if result.is_a?(Exception)
          puts "  → Failed with error:".red
          puts result
          puts result.backtrace
          puts "  → Please fix the error or mark the todo as done.".red
          puts "      #{@file_name}:#{line.source_code_line_index}".red
          exit 1
        end

        puts "  → Successfully executed".green
        puts
        line.mark_complete

        case Baker.plugins.run(:after_execution, line: line, baker: self, command: command, context: @context)
        when :skip
          next
        when :ask
          puts " ? Press y/Y to continue. Any other key to cancel and exit baker.".yellow
          exit(1) if prompt_user_choice(line) == :abort
          asked_before = true
        end # Fallthrough: :continue

      when :shell
        # system line.content

        if line.completed?
          next
        end
        require 'ostruct'
        o = OpenStruct.new(@context)
        o.singleton_class.define_singleton_method(:const_missing) { |name| o[name] }

        command = o.instance_eval("%(" + line.command + ")")

        if @context.has_key?('WRAP_COMMAND') && @context['WRAP_COMMAND'].to_s.strip != ""
          context = @context.dup

          context['COMMAND'] = command

          o = OpenStruct.new(context)
          o.singleton_class.define_singleton_method(:const_missing) { |name| o[name] }
          command = o.instance_eval("%(" + @context['WRAP_COMMAND'] + ")", @file_name, line.source_code_line_index)
        end

        # Apply indentation and any additional formatting
        to_display = format_command(command, max_line_length = 160)
        line_will_break = to_display =~ /\n/ || to_display.length > 80
        to_display = "\n#{to_display}\n" if line_will_break && to_display.scan(/\n/).length == 1

        # Replace all trailing whitespace with ·
        to_display = to_display.gsub(/\s(?=\s*$)/, '·')

        to_display = to_display.indent(1).gsub(/^/, '▐').indent(3) if line_will_break

        if @interactive
          puts " → About to execute shell code: #{"\n" if line_will_break}#{to_display}".yellow
        end

        asked_before = false
        case Baker.plugins.run(:before_execution, line: line, baker: self, command: command, context: @context)
        when :skip
          next
        when :ask
          puts " ? Press y/Y to continue. Any other key to cancel and exit baker.".yellow
          exit(1) if prompt_user_choice(line) == :abort
          asked_before = true
        end # Fallthrough: :continue

        if @interactive && !asked_before
          puts " ? Press y/Y to continue. Any other key to cancel and exit baker.".yellow

          exit(1) if prompt_user_choice(line) == :abort
        end

        puts (" → Executing shell code: #{"\n" if line_will_break}#{to_display}").yellow

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

            parser = VTParser.new do |action|
              print line_indent if first_line_indent
              first_line_indent = false

              to_output = action.to_ansi

              case action.action_type
              when :print, :execute, :put, :osc_put
                if action.ch == "\r"
                  print action.ch
                  print line_indent
                  next
                end
              when :csi_dispatch
                if to_output == "\e[2K"
                  print "\e[2K"
                  print line_indent
                  next
                else
                  if action.ch == 'G'
                    # puts "to_output: #{to_output.inspect} action: #{action} ch: #{ch.inspect}"
                    # && parser.params.size == 1
                    print "\e[#{action.params[0] + line_indent_width}G"

                    next
                  end
                end
              end

              print to_output
            end

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
              input_thread.join # Have to wait for the Thread to finish until we can proceed outputting text to the CLI
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
          puts "      #{@file_name}:#{line.source_code_line_index}".red
          exit 1
        end

        case Baker.plugins.run(:after_execution, line: line, baker: self, command: command, context: @context)
        when :skip
          next
        when :ask
          puts " ? Press y/Y to continue. Any other key to cancel and exit baker.".yellow
          exit(1) if prompt_user_choice(line) == :abort
          asked_before = true
        end # Fallthrough: :continue

      when :manual

        if line.completed?
          next
        end

        puts " → Perform the following steps manually:".yellow
        puts line.description

        allow_skip_permanently = !@no_save
        skip_message = "s to skip temporarily, #{"- or p to skip permanently, " if allow_skip_permanently}"
        puts
        puts " → Please enter: 'y' to confirm the task was completed, #{skip_message}or any other key to abort and exit baker.".yellow

        next if run_plugins(:before_execution, line: line) == :skip

        user_choice = prompt_user_choice(line, allow_skip: true)
        user_choice = 's' if user_choice == :skip_permanently && !allow_skip_permanently

        case user_choice
        
        when :continue
          line.mark_complete

        when :skip_temporarily
          skip_indent_level = line.indentation_level
          @skip_stack.push(skip_indent_level)

        when :skip_permanently
          
          # Mark this and all sub-task as permanently skipped
          line_indent = line.indentation_level
          
          first_line = true
          @recipe.steps[index..].each { |line|

            # Skip empty lines
            next if line.indentation_level == nil

            # Break if we are back to the same or higher indentation level
            break if !first_line && line.indentation_level <= line_indent
            first_line = false
            
            next if line.completed?

            puts " → Skipping permanently: #{line.single_line_for_display}".yellow

            line.mark_strikethrough
          }

        when :abort
          exit(1)
        end

        next if run_plugins(:after_execution, line: line) == :skip

      end

      save
    end

    puts " → All steps completed.".green

  end

  #
  # Prompt the user for input and return their choice.
  #
  def prompt_user_choice(line, allow_skip: false)
    begin
      answer = STDIN.gets().strip.downcase
    rescue Interrupt
      answer = ''
    end

    answer = '' if !allow_skip && ['s', '-', 'p'].include?(answer)

    case answer
    when 'y'
      return :continue
    when 's'
      return :skip_temporarily
    when '-', 'p'
      return :skip_permanently
    else
      require 'pathname'
      puts
      puts (' → Aborting as requested. Run `baker ' + Pathname.new(@file_name).relative_path_from(@original_dir).to_s + '` to continue.').green
      puts "   Current task: #{@file_name}:#{line.source_code_line_index}".green if line
      return :abort
    end
  end

  def save

    return if @no_save

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

  def run_plugins(block_type, line: nil)

    puts "Running plugins for block type: #{block_type}" if @debug

    case Baker.plugins.run(block_type, baker: self, line: line)
    when :skip
      return :skip
    when :ask
      puts " ? Press y/Y to continue. Any other key to cancel and exit baker.".yellow
      exit(1) if prompt_user_choice(line) == :abort
    end
  end

end

if __FILE__==$0
  Baker.new.run_safe
end