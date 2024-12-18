require 'parser/current'
require 'rubocop'
require 'rubocop/ast'

#
# method_selector can be a symbol, a method name as a string, a Rubocop::NodePattern, or 
# a String starting with an open parenthesis to indicate a Rubocop::NodePattern as a string. 
#
def insert_method_arg(code, method_selector, *positionals, **keywords)
  
  if method_selector.is_a?(Symbol) || (method_selector.is_a?(String) && !method_selector.start_with?('('))
    method_selector = "(send nil? :#{method_selector} ...)"
  end
  
  if (method_selector.is_a?(String) && method_selector.start_with?('('))
    method_selector = RuboCop::NodePattern.new(method_selector)
  end

  unless method_selector.is_a?(RuboCop::NodePattern) 
    raise ArgumentError, "method_selector must be a Symbol, String, or RuboCop::NodePattern"
  end

  ruby_version = RUBY_VERSION.split('.')[0..1].join('.').to_f
  source = RuboCop::ProcessedSource.new(code, ruby_version)
  source_buffer = source.buffer
  rewriter = Parser::Source::TreeRewriter.new(source_buffer)
  rule = AddToParamHashRule.new(rewriter, method_selector, positionals, keywords)
  source.ast.each_node { |n| rule.process(n) }
  new_code = rewriter.process
  new_code
end

class AddToParamHashRule < Parser::AST::Processor
  include RuboCop::AST::Traversal
  
  def initialize(rewriter, node_pattern, positionals, keywords)
    @rewriter = rewriter
    @node_pattern = node_pattern
    @positionals = positionals
    @keywords = keywords
    @processed_nodes = Set.new # To avoid processing the same node twice within a run
  end
  
  def on_send(node)
    if @processed_nodes.include?(node.object_id)
      # puts "Skipping already processed node #{node.object_id}: #{node}"
      return
    end
    @processed_nodes << node.object_id
    
    # Check if the node matches the desired pattern
    return unless @node_pattern.match(node)

    # Insert positionals first
    new_positionals = @positionals.reject { |p| argument_exists?(node.arguments, p) }
    insert_positionals(node, new_positionals) unless new_positionals.empty?
        
    # Insert keywords
    unless @keywords.empty?
      insert_keywords(node, @keywords, new_positionals.empty?)
    end
  end

 private

 def argument_exists?(args, val)
   # For simplicity, we'll only check symbol and string arguments by simple equality
   # Extend this as needed for more complex checks.
   args.any? do |arg|
     (arg.sym_type? && arg.value == val) ||
       (arg.str_type? && arg.str_content == val.to_s)
   end
 end

 def insert_positionals(node, new_positionals)
   # If no arguments yet, insert right after the method name
   # If there are arguments, insert after the last argument before any keyword hash
   last_arg_end = if node.arguments.empty?
                    node.loc.expression.end_pos
                  else
                    node.arguments.last.loc.expression.end_pos
                  end

   insertion_str = new_positionals.map { |p| arg_to_source(p) }

   # If there are existing arguments, join with ", "
   # If no arguments, prefix with a space
   prefix = node.arguments.empty? ? " " : ", "
   final_str = prefix + insertion_str.join(", ")

   @rewriter.insert_after(create_range(last_arg_end), final_str)
 end

 def insert_keywords(node, keywords, no_new_positionals)
  args = node.arguments

  hash_arg = args.last if args.last&.hash_type?

  if hash_arg
    # Merge keywords into existing hash argument
    merge_keywords_into_hash(hash_arg, keywords)
  else
    # Insert keywords as normal keyword args
    # e.g. devise_for :users, foo: "bar"
    # If arguments exist: devise_for :users, :admin, foo: "bar"
    insertion_point = args.empty? ? node.loc.expression.end_pos : args.last.loc.expression.end_pos
    insertion_str = if args.empty? && no_new_positionals
                       " " + keywords_to_source(keywords)
                     else
                       ", " + keywords_to_source(keywords)
                     end
    @rewriter.insert_after(create_range(insertion_point), insertion_str)
  end
end

def merge_keywords_into_hash(hash_node, keywords)
  # hash_node is an AST node representing a hash like { controllers: { ... }, class_name: "..." }
  # We must integrate the new keywords into this hash node.

  # Existing keys in the hash node
  existing_pairs = hash_node.pairs
  existing_keys = existing_pairs.map { |p| p.key.value if p.key.sym_type? }.compact

  keywords.each do |k, v|

    if existing_keys.include?(k)
      # Key exists
      existing_pair = existing_pairs.find { |p| p.key.value == k }
      if existing_pair.value.hash_type? && v.is_a?(Hash)
        # Both old and new values are hashes, recursively merge
        merge_keywords_into_hash(existing_pair.value, v)
      else
        # Both values are non-hash. Check if their string representations match.
        existing_val_str = existing_pair.value.source
        new_val_str = arg_to_source(v)

        if existing_val_str == new_val_str
          # They match exactly, so do nothing.
        else
          raise "Don't know how to merge existing value #{existing_val_str.inspect} with new value #{new_val_str.inspect}"
        end
      end
    else
      # New key, insert at the end of the hash
      insertion_point = hash_node.loc.end.begin_pos
      insertion_str = existing_pairs.empty? ? "" : ", "
      insertion_str += "#{k}: #{arg_to_source(v)}"
      insertion_str = " #{insertion_str} " if existing_pairs.empty?

      if remove_trailing_space_before(insertion_point)
        insertion_str += " "
      end

      @rewriter.insert_before(create_range(insertion_point), insertion_str)
      # Update the pairs/keys caches (not strictly necessary if we rely on one pass)
      existing_pairs << nil # placeholder, actual node won't update in memory but we won't re-run during same execution
      existing_keys << k
    end
  end
end

def remove_trailing_space_before(pos)
  # If there's a space before the insertion point, remove it
  src = @rewriter.source_buffer.source
  if pos > 0 && src[pos - 1] == ' '
    space_range = Parser::Source::Range.new(@rewriter.source_buffer, pos - 1, pos)
    @rewriter.remove(space_range)
    return true
  end
  return false
end

def keywords_to_source(keywords)
  # Convert a hash of keywords into a string like `foo: "bar", controllers: { ... }`
  keywords.map { |k,v| "#{k}: #{arg_to_source(v)}" }.join(", ")
end

def arg_to_source(value)
  case value
  when Symbol
    ":#{value}"
  when String
    value.inspect
  when Hash
    # { key: value, ... }
    inner = value.map { |k, v| "#{k}: #{arg_to_source(v)}" }.join(", ")
    "{ #{inner} }"
  else
    value.inspect
  end
end

 def create_range(pos)
   Parser::Source::Range.new(@rewriter.source_buffer, pos, pos)
 end
end

