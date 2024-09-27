# frozen_string_literal: true

require_relative "baker/version"

require 'fileutils'
require 'ostruct'
require 'rails/generators'
require "tty-prompt"
require 'rainbow/refinement'
using Rainbow
require_relative 'baker/bakerlib'

class Baker

  attr_accessor :debug
  attr_accessor :recipe

  def process_args

    @debug = false
    
    # Process ARGS:
    #   -d = Debug
    #   -f = Show Future Window
    #   -r=YYYYMMDD = Simulate Recurring Tasks for the given date and exit
    while ARGV[0] =~ /^-+(\w)(.*)$/
      case $1
      when "d"
        @debug = true
      else
        puts "Unknown option: #{$1}"
        exit(1)
      end
      ARGV.shift
    end

    # If no file is given, assume the user wants to edit "~/plan.md"
    if ARGV.empty?
      @file_name = "template.md"
      Dir.chdir Dir.home
    else
      @file_name = ARGV[0]
    end

    @file_name = File.expand_path(@file_name)

    return nil
  end

  def expand_vars(input)

    return "" if input.nil? || input.empty?

    o = OpenStruct.new(@context)
    o.singleton_class.define_singleton_method(:const_missing) { |name| o[name] }
    
    return o.instance_eval(input)
  end

  def run

    status = process_args
    return if status == :close

    @file_contents = File.read(@file_name)
    
    @recipe = Recipe.from_s(@file_contents)
    
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

            line.attributes = TTY::Prompt.new.ask(" → Please enter your value for variable '#{line.content}':\n".yellow, value: initial_value)
            # line.attributes = STDIN.gets().strip
            line.lines = ["::var[#{line.content}]{#{line.attributes}}"]
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

            exit(1) if STDIN.gets().strip.downcase != 'y'
          end
          line.delete

          puts ""

          @file_name = template_name_suggestion
          save
          next
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
        o = Struct.new(*@context.keys).new(*@context.values)
        # require 'ostruct'
        # o = OpenStruct.new(@context)
        o.singleton_class.define_singleton_method(:const_missing) { |name| o[name] }
        o.extend Forwardable
        o.def_delegators :rails_gen_base, :inject_into_file, :gsub_file, :create_file, :copy_file, :insert_into_file, :inside, :environment, :gem, :generate, :git, :initializer, :lib, :rails_command, :rake, :route

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

        if !result.is_a?(Exception)
          puts "  → Successfully executed".green
          line.mark_complete
        else
          puts "  → Failed with error:".red
          puts result
          puts result.backtrace
          puts "  → Please fix the error or mark the todo as done.".red
          exit 1
        end        

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
        puts " ? Do you want to overwrite the file? Enter y/Y to overwrite. Any other key to cancel and exit baker.".yellow
        input = STDIN.gets()
        if input.strip.downcase != 'y'
          puts " → Exiting without saving. Please manually mark the successfully executed steps as done.".red
          exit 1
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