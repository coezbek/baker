
#
# Register a plugin with Baker call:
#
# Baker.plugins.register(:trigger) do
#   # Your code here
# end
#
# The following triggers/hook types are availabe:
#
#  :before_load, :after_load           - before/after the baker file is loaded
#  :before_line                        - before the line is undergoing variable expansion. Will be called even for lines which are completed ([x])
#  :before_expansion, :after_expansion - before/after the line is undergoing variable expansion.
#  :before_execution                   - before the line is executed.
#  :after_execution                    - after the line is executed which includes printing error messages and marking the line as completed
#  :before_save, :after_save           - before/after the baker file is saved (which happens after each line with a task/command)
#  :all                                - all of the above
#
# In the &block access is available to the following variables:
#   line, baker, command, context 
#
# You might want to filter based on the line.type if your plugin is active or not:
#  - :shell - shell command block
#  - :ruby - ruby code block
#  - :manual - manual task block
#  - :directive - directive block
#  - :nop - Text, comment, empty line
#
# The &block can return any of the following:
#
#  - :exit or false           - abort processing and exit
#  - :skip                    - skip this block
#  - :ask                     - ask the user if they want to continue
#  - :continue, true or nil   - continue processing
class Plugins

  def init
    Dir[File.dirname(__FILE__) + '/plugins/*.rb'].each do |file|
      require file
    end
  end
  
  ALL_TRIGGERS = [
    :before_load, :after_load, 
    :before_line, 
    :before_expansion, :after_expansion, 
    :before_execution, :after_execution, 
    :before_save, :after_save
  ]

  def register(action_type, &block)

    # Unroll arrays
    action_type.each do |at| register(at, &block) end if action_type.is_a?(Array)
    
    # Unroll :any
    action_type = :any if action_type == :all
    ALL_TRIGGERS.each do |at| register(at, &block) end if action_type == :any
     
    raise "Action type must be one of #{ALL_TRIGGERS.inspect} but is #{action_type}" unless ALL_TRIGGERS.include?(action_type)

    @plugins ||= {}
    @plugins[action_type] ||= []
    @plugins[action_type] << block
  end

  #
  # Runs all registered plugin with the given block_type and action_type
  #
  # Returns: :continue, :skip, :ask
  #
  def run(action_type, line:, baker:, command:, context:)

    raise "Action type must be one of #{ALL_TRIGGERS.inspect} but is #{action_type}" unless ALL_TRIGGERS.include?(action_type)

    @plugins.dig(action_type)&.each do |block|

      result = OpenStruct.new(line: line, baker: baker, command: command, context: context).instance_eval(&block)

      #  - :exit or false           - abort processing and exit
      #  - :skip                    - skip this block (skips all other plugins)
      #  - :ask                     - ask the user if they want to continue
      #  - :continue, true or nil   - continue processing
      case result
      when :exit, false
        exit(1)
      when :skip
        return :skip
      when :ask
        return :ask
      when :continue, true, nil
        next
      else 
        raise "Unknown return value from plugin block: #{result.inspect}"
      end

    end
    return :continue
  end

end