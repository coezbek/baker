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
    multiline_ruby = nil
    s.each_line.with_index { |line, index|
      index += 1 # 1-based index

      if multiline_ruby
        if line =~ /^\s*```/
          
          multiline_ruby[:lines] << line

          j.steps << RecipeStep.new(
            multiline_ruby[:lines], 
            type: :ruby, 
            task_marker: multiline_ruby[:task_marker], 
            command: multiline_ruby[:command].join, 
            description: multiline_ruby[:description],
            line_index: multiline_ruby[:line_index])
          
          multiline_ruby = nil

        else
          multiline_ruby[:lines] << line
          multiline_ruby[:command] << line
        end
        next
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

      elsif line =~ /^\s*(-\s+)?\[(.)\]\s(?:(.*?):)?\s*```(.*$)/m
      
        multiline_ruby = {lines: [line], task_marker: $2, description: $3, command: [$4], line_index: index}
        
      elsif line =~ /^\s*(-\s+)?\[(.)\]\s*(.*)/

        j.steps << RecipeStep.new(line, type: :manual, task_marker: $2, description: $3, line_index: index)
      
      else
        j.steps << RecipeStep.new(line, type: :nop, line_index: index)
      end
    }

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
    raise "Not a directive" if type != :directive
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

  # Returns the number of leading spaces of the given line
  def indent_depth(line_index)
    return nil if !lines[line_index] || lines[line_index].strip.length == 0

    lines[line_index][/\A\s*/].length
  end

  # Returns the line index of the parent line if any or nil
  # The parent line is the line with a reduced indentation or the section header in case there no reduced indented line
  def parent_index(line_index)
    j = line_index - 1
    my_indent = indent_depth(line_index)
    return nil if !my_indent
    while j > 0 # Day header does not count as parent
      other_indent = indent_depth(j)
      if other_indent && other_indent < my_indent
        return j
      end
      j -= 1
    end
    return nil
  end

  # Turns the linear list of lines of this TodoDay into a nested structure of the form
  # [{text: "text", children: [...]}, ...]
  # where ... is the same hash structure {text: "text", children: [...]}
  def structure

    indents = [nil] * lines.size
    (lines.size - 1).downto(0).each { |i|
      indents[i] = indent_depth(i) || (i+1 < indents.size ? indents[i+1] : 0)
    }

    stack = [{depth: -1, children: []}]
    lines.each_with_index { |s, i|
      indent = indents[i]
      new_child = {depth: indent, text: s, index: i, children: []}
      while indent <= stack.last[:depth]
        stack.pop
      end
      stack.last[:children] << new_child
      stack << new_child
    }

    return stack.first[:children]
  end

  def is_any_open?
    return lines.any? { |line| line =~ /^\s*(-\s+)?\[\s\]/ }
  end

  def is_closed?
    return !is_any_open?
  end

end