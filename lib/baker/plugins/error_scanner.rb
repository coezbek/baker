require 'rainbow/refinement' # for string colors 
using Rainbow

#
# This plugin scans the output of the previously run command for warnings or errors.
# 
# This is necessary, because not all programs return a non-zero exit code when they encounter a problem.
#
# If a warning or error is found, it pauses the Baker run, prints the error with context,
# and asks the user if they want to continue.

Baker.plugin.register(:after_execution) do
  
  # Only shell commands have output
  next unless line.type == :shell

  # We only review the command output for programs which claim that the successfully terminated
  next unless output[:successfully_terminated] == true

  no_of_warnings = output[:command_output].scan(/\b(?<!0\s)(?<!no\s)(?<!without\s)(error|warn|fatal|critical)/i).size

  if no_of_warnings > 0

    print "Shell command termianted successfully, but ".red
    if no_of_warnings == 1
      puts "a warning/error was found in command output:".red
    else
      puts "#{no_of_warnings} warnings/errors were found in command output. The first is shown below:".red
    end
    puts ">>>".yellow
    puts first_warning_with_context(output[:command_output])
    puts "<<<".yellow
    puts "      Source: #{baker.file_name}:#{line.line_index}".yellow

    next :ask
  end

  next :continue
end

def first_warning_with_context(output)
  # Color codes for red text
  red = "\e[31m"
  reset = "\e[0m"

  # Split the output into lines
  lines = output.lines

  # Find and print the first match with context
  lines.each_with_index do |line, i|
    if line =~ /warn|error|fatal/i
      # Highlight keywords 'warn', 'error', and 'fatal'
      highlighted_line = line.gsub(/(warn|error|fatal)/i, "#{red}\\1#{reset}")

      # Capture context: previous line, matching line, next line
      return [
        i > 0 ? lines[i - 1] : nil,             # previous line
        highlighted_line,                       # current line (highlighted)
        i < lines.size - 1 ? lines[i + 1] : nil # next line
      ].compact.join
    end
  end
end