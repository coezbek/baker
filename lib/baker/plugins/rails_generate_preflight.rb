
require 'rainbow/refinement' # for string colors 
using Rainbow
#
# This plugin validates the arguments of the 'rails generate' command for common mistakes.
#
# Only looks at model scaffold controller migration
#
Baker.plugin.register(:before_execution) do

  next unless line.type == :shell

  next unless command =~ /^\s*(bin\/)?rails\s+g(enerate)?/

  warnings = validate_rails_command(command)
  unless warnings.empty?
    puts "Rails Command validation found warnings:".red
    warnings.each do |warning|
      puts "  - WARN: #{warning}".red
    end
    puts "      Source: #{baker.file_name}:#{line.line_index}".yellow
    next :ask
  end
  next :continue
end

def validate_rails_command(command_line)
  require 'active_support/core_ext/string/inflections'
  require 'shellwords'

  warnings = []
  options = []

  # Normalize and split the command line
  command_line = command_line.strip
  tokens = Shellwords.shellsplit(command_line)

  raw_tokens = command_line.split(/\s+/)
  raw_tokens.each { |token|
    if token =~ /\{\d+\s*,\s*\d+\}/ && !(token.strip.start_with?('\'') && token.strip.end_with?('\''))
      warnings << "Need to escape {x,y} to avoid conflict with shell."
    end
  }

  # Remove prefixes
  prefixes = ['rails', 'g', 'generate', 'bin/rails']
  tokens.shift while prefixes.include?(tokens.first)

  if tokens.empty?
    warnings << "No generator type specified."
    return warnings
  end

  generator_type = tokens.shift

  unless %w[model scaffold controller migration].include?(generator_type)
    # We only handle the known generator type
    return warnings
  end

  if tokens.empty?
    warnings << "No name specified for the generator."
    return warnings
  end

  name = tokens.shift

  reserved_model_fields = %w[
    type id attributes position parent_id lft rgt
    created_at created_on updated_at updated_on deleted_at lock_version
    accept action attributes callback category connection database dispatcher 
    drive errors format host key layout load link new notify open public quote
    render request records responses save scope send session system template 
    test timeout to_s type visits lock_version quote_value and not or
    alias begin break case class def else do
    elsif end ensure  for if module next  redo rescue retry 
    return self false true nil super then  undef unless until when while yield
  ]

  # Check naming conventions
  case generator_type
  when 'model', 'scaffold'
    expected_name = name.camelize.singularize
    unless name == expected_name
      warnings << "Model name '#{name}' should be singular and in CamelCase (e.g., '#{expected_name}')."
    end
  when 'controller'
    expected_name = name.camelize
    unless name == expected_name
      warnings << "Controller name '#{name}' should be in CamelCase (e.g., '#{expected_name}')."
    end

    if Dir.glob("app/models/*.rb").any? { |filename| File.basename(filename, ".*").camelize == name }
      warnings << "Controller name matches an existing model '#{name}'. Did you want to create a controller for this model? Use plural form '#{name.pluralize}'."
    end

    # For controller, the remaining tokens are action names
    action_names = tokens
    action_names.each do |action|
      if action.start_with?('--')
        options << action
      else

        reserved_actions = %w[
          send object_id class method initialize freeze exit loop raise fork eval 
          alias break begin end save valid invalid errors reload attributes all 
          head render redirect_to params session request response controller action
        ]

        # Optionally validate action names
        if reserved_actions.include?(action.downcase)
          warnings << "Action name '#{action}' might conflict with existing rails controller methods."
        end
      end
    end
    # Skip attribute validation for controllers
    return warnings
  end

  # Separate attributes and options
  attributes = []

  tokens.each do |token|
    if token.start_with?('--')
      options << token
    else
      attributes << token
    end
  end

  # Supported types
  supported_types = %w[
    binary boolean date datetime decimal float integer string text time timestamp references
  ]
  
  # Validate attributes
  attributes.each do |attr|
    # Split attribute into name and type with modifiers
    attr_parts = attr.split(':', 2)
    attr_name = attr_parts[0]
    attr_type_and_modifiers = attr_parts[1]

    if attr_name.nil? || attr_name.empty?
      warnings << "Invalid attribute format '#{attr}'."
      next
    end

    if reserved_model_fields.include?(attr_name.downcase)
      warnings << "Attribute name '#{attr_name}' is a reserved word."
    end

    unless attr_type_and_modifiers
      warnings << "No type specified for attribute '#{attr_name}'."
      next
    end

    # Extract type and modifiers
    if attr_type_and_modifiers =~ /^(\w+)(\{[^}]*\})?$/
      attr_type = $1
      modifiers = $2
    else
      warnings << "Invalid attribute format '#{attr}'."
      next
    end

    unless supported_types.include?(attr_type)
      warnings << "Attribute type '#{attr_type}' is not supported."
    end

    if attr_type == 'references' && attr_name != attr_name.singularize
      warnings << "Reference attribute '#{attr_name}' should be singular (e.g., '#{attr_name.singularize}')."
    end

    if attr_type == 'decimal' && modifiers && !(modifiers =~ /\{(\d+)\s*[,-]\s*\d+\}/)
      warnings << "Decimal modifier should be {precision,scale}."
    end

    if modifiers
      if !modifiers.match(/^\{[\w,]+\}$/)
        warnings << "Modifiers '#{modifiers}' for attribute '#{attr_name}' are not properly formatted. Use '{...}'."
      end
    end
  end

  # Allowed options
  allowed_options = %w[
    --skip-routes --skip-assets --skip-helper --skip-test-framework
    --skip-template-engine --skip-stylesheets
    # Include all other allowed options
  ]

  options.each do |option|
    unless allowed_options.include?(option)
      warnings << "Option '#{option}' is not allowed."
    end
  end

  warnings
end
