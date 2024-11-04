require 'yaml'

class BakerConfig

  def initialize(filename)
    @filename = filename

    if !File.exist?(filename)
      @config = {}
    else
      @config = YAML.load_file(filename)
    end
  end

  def [](*args)
    @config.dig(*args)
  end

  def []=(*args, key, value)
    last = args.inject(@config) do |memo, key|
      memo[key] ||= {}
      memo[key]
    end
    last[key] = value
  end

  def flush
    File.open(@filename, 'w') do |f|
      f.write(@config.to_yaml)
    end
  end

end