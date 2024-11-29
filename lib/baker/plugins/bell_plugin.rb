require 'rainbow/refinement' # for string colors 
using Rainbow
#
# This plugin rings the bell to notify the user that manual input is needed 
# if more than 5 seconds have passed since the last manual interaction.
#
# Disable with --no-bell
#
@no_bell = false
Baker.plugin.register(:before_options) do
  
  baker.opts.on('--no-bell', 'Disable bell to notify manual input is needed') do
    @no_bell = true
  end
  
  next :continue
end

Baker.plugin.register(:after_options) do
  
  next if @no_bell
  last_task_started = Time.now

  Baker.plugin.register([:before_execution, :after_execution_complete]) do
    
    # puts "Since last manual input #{Time.now - last_task_started} seconds have passed." if baker.debug
    
    next unless line.type == :manual

    case action_type
    when :before_execution

      if Time.now - last_task_started >= 5.0
        print "\a" # Ring the bell
      end

    when :after_execution_complete

      # puts "Resetting time to #{Time.now}." if baker.debug
      last_task_started = Time.now

    end

    next :continue
  end

  next :continue  
end
