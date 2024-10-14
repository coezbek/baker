require 'date'

#
# Recipe is the datastore class for the task list managed by baker
#
# Responsible for:
#   - Parsing a md file into a Recipe
#   - Serialization back into a md file
#
class Recipe

  # Array of `RecipeStep`s
  attr_accessor :steps
  
  def self.from_s(s)

    j = Recipe.new
    j.steps = []
    
    next_day = []
    multiline = nil
    s.each_line.with_index { |line, index|
      index += 1 # 1-based index

      if multiline
        multiline[:lines] << line

        case multiline[:multiline_type]
        when :ruby, :shell

          if line =~ /^\s*```\s*$/
            
            multiline[:command] << $1

            j.steps << RecipeStep.new(
              multiline[:lines], 
              type: multiline[:multiline_type], 
              task_marker: multiline[:task_marker], 
              command: multiline[:command].join, 
              description: multiline[:description],
              line_index: multiline[:line_index])
            
            multiline = nil
            next
          end

          # Multiline continues just collect items.
          multiline[:command] << line
          next

        when :unknown

          # If line starts with ``` we have a new block
          if line =~ /^\s*```(.*\z)/m

            # If this block starts with ```bash or ```sh we have a shell block
            command = $1
            if command.strip == "bash" || command.strip == "sh"
              multiline[:multiline_type] = :shell
              next
            end

            # All other blocks are considered ruby blocks
            multiline[:multiline_type] = :ruby

            if command =~ /^(.*)```\s*$/
              # Ruby block terminated on same line
              command = $1
              raise if multiline[:command].size > 0
              
              j.steps << RecipeStep.new(
                multiline[:lines],
                type: multiline[:multiline_type],
                task_marker: multiline[:task_marker],
                command: command,
                description: multiline[:description],
                line_index: multiline[:line_index])

              multiline = nil
              next
            end 

            if command.strip != "ruby" && command.strip.size > 0
              multiline[:command] << command
            end
            next
          end
            
          # Line did not start with ```

          j.steps << RecipeStep.new(
            multiline[:lines],
            type: :manual,
            task_marker: multiline[:task_marker],
            description: multiline[:description],
            line_index: multiline[:line_index])

          multiline = nil
        
          # IMPORTANT: Don't call next here, we continue processing this line as a normal line

        else
          raise "Unknown or missing multiline type: #{multiline[:multiline_type]}"
        end
      end

      if line =~ /^::(\w*?)(?:\[(.*?)\])?(?:\{(.*)\})?\s*$/
        directive = $1.downcase
        content = $2
        attributes = $3

        # puts "Directive: '#{directive}' - Content: '#{content}' Attributes: '#{attributes}'"

        case directive
        when "template"
          j.steps << RecipeStep.new(line, type: :directive, directive_type: :template, content: content, attributes: attributes, line_index: index)
        when "template_source"
          j.steps << RecipeStep.new(line, type: :directive, directive_type: :template_source, content: content, attributes: attributes, line_index: index)
        when "var"
          j.steps << RecipeStep.new(line, type: :directive, directive_type: :var, content: content, attributes: attributes, line_index: index)
        when "cd"
          j.steps << RecipeStep.new(line, type: :directive, directive_type: :cd, content: content, line_index: index)
        else
          raise "Unknown directive: #{directive}"
        end

      elsif line =~ /^\s*(-\s+)?\[(.)\]\s*(?:(.*?):)?\s*`([^`]+)`/

        j.steps << RecipeStep.new(line, type: :shell, task_marker: $2, command: $4, description: $3, line_index: index)

      elsif line =~ /^\s*(-\s+)?\[(.)\]\s*(?:(.*?):)?\s*``([^`].*?)``/

        j.steps << RecipeStep.new(line, type: :ruby, task_marker: $2, command: $4, description: $3, line_index: index)

      # General case in which a multiline task might be started
      # We will try to find the last colon to separate description and command unless there is a backtick after a colon
      elsif line =~ /^\s*(-\s+)?\[(.)\]\s(?:(.*?):(?=\s*`)|(.*):(?=[ \n]))?\s*(.*\z)/m

        task_marker = $2
        description = $3 || $4
        command = $5

        # Command starts with ``` => Ruby command block
        if command =~ /^```(.*\z)/m
          command_block_type = :ruby
          command = $1
          if command.strip == "ruby"
            command = "" # Ignore markdown block designator for ruby
          end
          if command =~ /^(.*)```\s*$/
            # Ruby block terminated on same line
            command = $1
            j.steps << RecipeStep.new(line, type: :ruby, 
              task_marker: task_marker, command: command, description: description, line_index: index)
          else # Multiline ruby command started
            commands = []
            if command.strip.size > 0
              commands << command
            end
            multiline = {
              lines: [line], 
              multiline_type: :ruby,
              task_marker: task_marker, description: description, command: commands, line_index: index
            }
          end
        else # Block doesn't start with ````
          if command.strip.size > 0
            # Not a ``` block but just other text after a colon

            description = (description ? [description, command].join(": ") : command).chomp
            j.steps << RecipeStep.new(line, type: :manual, task_marker: task_marker, description: description, line_index: index)
          else
            # Empty line after colon, we don't know yet what comes next
            multiline = {
              lines: [line], 
              multiline_type: :unknown,
              task_marker: task_marker, description: description, command: [], line_index: index
            }
          end
        end
        
      elsif line =~ /^\s*(-\s+)?\[(.)\]\s*(.*\z)/m

        j.steps << RecipeStep.new(line, type: :manual, task_marker: $2, description: $3, line_index: index)
      
      else
        j.steps << RecipeStep.new(line, type: :nop, line_index: index, description: line.chomp)

      end
    }
    if multiline
      raise "Unterminated multiline block. Are you missing closing triple backticks ``` on an empty line?" 
    end
    return j
  end

  def to_s
    result = []

    empty = false
    steps.each { |step| 
      if step.lines.empty? 
        empty = true
      else
        # if we encountered a deleted line (empty array), we skip all blank lines until we encounter a non-blank line
        if empty && step.lines.all? { |line| line.strip.size == 0 }
          # nothing
        else
          empty = false
          result << step.to_s
        end
      end
    }

    return result.join # + (empty ? "" : "\n")
  end

end

# Encapsulate a single date of todo information
class RecipeStep

  # Lines are expected to contain the line end character "\n"
  attr_accessor :lines
  attr_accessor :type
  attr_writer :attributes
  attr_reader :line_index

  def initialize(lines, type: , directive_type: nil, content: nil, attributes: nil, command: nil, task_marker: nil, description: nil, line_index: nil)
    if lines.is_a?(Array)
      @lines = lines
    else
      @lines = [lines]
    end
    @type = type
    @directive_type = directive_type
    @content = content
    @attributes = attributes
    @command = command
    @task_marker = task_marker
    @description = description
    @line_index = line_index
  end

  def delete
    self.lines = []
  end

  def to_s
    lines.join
  end

  def completed?
    case type
    when :directive
      case directive_type
      when :var
        return attributes != nil
      when :template
        return false
      end
      raise "Unknown directive type: #{directive_type}"
    when :shell, :manual, :ruby
      return task_marker != " "
    else
      return true
    end
  end

  def mark_complete
    if lines[0] =~ /\[\s\]/
      lines[0].sub!(/\[\s\]/, "[x]")
      @task_marker = "x"
    else
      puts lines.inspect
      raise
    end
  end

  def mark_todo
    if lines[0] =~ /\[[xX\-.y]\]/
      lines[0].sub!(/\[[xX\-.y]\]/, "[ ]")
      @task_marker = " "
    else
      puts lines.inspect
      raise
    end
  end

  def directive_type
    raise "Not a directive" if type != :directive
    return @directive_type
  end

  def content
    raise "RecipeStep.content is only valid for a directive, but is #{type}" if type != :directive
    return @content
  end

  def attributes
    raise "Not a directive" if type != :directive
    return @attributes
  end

  def command
    raise "Not a shell" if type != :shell && type != :ruby
    return @command
  end

  def task_marker
    raise "Not a task" if type != :shell && type != :manual && type != :ruby
    return @task_marker
  end

  def description
    return @description
  end

end