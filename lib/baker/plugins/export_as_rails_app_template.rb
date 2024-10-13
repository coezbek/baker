require 'rainbow/refinement' # for string colors 
using Rainbow
#
# This plugin exports a baker file as a Rails Application Template
#
Baker.plugin.register(:before_options) do

  baker.opts.on('--rails-app-template', 'Export as a Rails Application Template to STDOUT') do

    Baker.plugin.register(:after_load) do

      first_empty_line = true
      baker.recipe.steps.each do |line|

        case line.type
  
        when :directive
          case line.directive_type
          when :var
            puts "#{line.content}=\"#{line.attributes}\""
          when :cd
            puts "Dir.chdir('#{line.content}')"
          when :template
            # Skip, because the export is like a template itself
          when :template_source
            puts "# This template was generated from #{line.content}"
          else
            puts "# Unknown directive: #{line.directive_type}"
          end
        
        when :shell
          puts "# #{line.description}" if line.description
          puts "`#{line.command}`"

        when :ruby
          puts "# #{line.description}" if line.description
          puts line.command

        when :manual
          puts "puts 'Manually do: #{line.description}'"
          puts "exit(1) unless yes?('Did you complete it?')"

        when :nop
          if line.description

            if line.description.strip.length == 0
              puts "" if first_empty_line
              first_empty_line = false
              next
            else
              puts "# #{line.description.sub(/^\s*[#\-]\s*/, '')}"
            end

          end
        else
          raise "Unknown line type: #{line.type}"
        end

        first_empty_line = true
      end

      next :exit
      
    end

  end

  next :continue
end
