# frozen_string_literal: true

require_relative "baker/version"

require 'optparse'
require 'tempfile'
require 'fileutils'
require 'ostruct'
require 'rails/generators'
require "tty-prompt"
require 'rainbow/refinement'
using Rainbow
require 'ap'
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

    puts "Bake File: #{@file_name}".yellow if @debug

    return nil
  end

  def expand_vars(input)

    return "" if input.nil? || input.empty?

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
        
        puts (" → Executing ruby code: #{command.inspect}").yellow

        begin
          result = o.instance_eval(command)
        rescue Exception => e
          result = e
        end

        if result == false
          # We assume the ruby command outputted an error message
          puts "  → Please fix the error or mark the todo as done.".red
          exit 1
        end

        if result.is_a?(Exception)
          puts "  → Failed with error:".red
          puts result
          puts result.backtrace
          puts "  → Please fix the error or mark the todo as done.".red
          exit 1
        end        
      
        puts "  → Successfully executed".green
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
        puts " → Executing shell command: #{command.inspect}".yellow
        
        puts ">>>>>>".white
        result = system(command, out: STDOUT) # , exception: true
        puts ">>>>>>".white
        puts ""

        if result
          puts "  → Successfully executed".green
          line.mark_complete
        else
          puts "  → Failed with error:".red
          puts $?
          puts "  → Please fix the error or mark the todo as done.".red
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
  Baker.new.run
end