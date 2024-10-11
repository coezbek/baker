
#
# Reload gem paths after running a gem install command
#
Baker.plugin.register(:after_execution) do

  next unless line.type == :shell

  if line.command =~ /^\s*gem\s+install\s+/
    puts "Reloading gem paths..."
    Gem.clear_paths
  end

end
