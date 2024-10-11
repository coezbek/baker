# spec/test_rails_preflight_spec.rb
require 'rspec'
require_relative '../lib/baker'
require_relative '../lib/baker/plugins/rails_generate_preflight'

RSpec.describe Baker do

describe '#validate_rails_command' do
  context 'when command is valid' do
    it 'accepts a valid model generation command' do
      command = 'rails generate model User name:string age:integer'
      expect(validate_rails_command(command)).to be_empty
    end

    it 'accepts a valid controller generation command' do
      command = 'rails generate controller Users index show'
      expect(validate_rails_command(command)).to be_empty
    end

    it 'accepts a valid model with attributes and options' do
      command = 'rails generate model Product name:string \'price:decimal{10,2}\' --skip-routes'
      expect(validate_rails_command(command)).to be_empty
    end

    it 'accepts a model with alias type bool' do
      command = 'rails generate model User active:bool'
      expect(validate_rails_command(command)).to include("Attribute type 'bool' is not supported.")
    end

    it 'accepts a model with references type' do
      command = 'rails generate model Post user:references'
      expect(validate_rails_command(command)).to be_empty
    end
  end

  context 'when command has naming convention issues' do
    it 'warns if model name is plural' do
      command = 'rails generate model Users name:string'
      expect(validate_rails_command(command)).to include(
        "Model name 'Users' should be singular and in CamelCase (e.g., 'User')."
      )
    end

    it 'warns if controller name is lowercase' do
      command = 'rails generate controller User index'
      expect(validate_rails_command(command)).to be_empty
    end
  end

  context 'when command has reserved words' do
    it 'warns if attribute name is a reserved word' do
      command = 'rails generate model User class:string'
      expect(validate_rails_command(command)).to include("Attribute name 'class' is a reserved word.")
    end

    it 'warns if attribute name is "type"' do
      command = 'rails generate model User type:string'
      expect(validate_rails_command(command)).to include("Attribute name 'type' is a reserved word.")
    end

    it 'warns if attribute name is "id"' do
      command = 'rails generate model User id:integer'
      expect(validate_rails_command(command)).to include("Attribute name 'id' is a reserved word.")
    end

    it 'warns if attribute name is' do
      command = 'rails generate scaffold Requisition name:string request:string first_execution:datetime rrule:string description:text requester:references reporter:references'
      expect(validate_rails_command(command)).to include("Attribute name 'request' is a reserved word.")
    end
      
  end

  context 'when command has unsupported attribute types' do
    it 'warns if attribute type is unsupported' do
      command = 'rails generate model User name:str'
      expect(validate_rails_command(command)).to include("Attribute type 'str' is not supported.")
    end
  end

  context 'when command has reference attribute issues' do
    it 'warns if reference attribute name is plural' do
      command = 'rails generate model Post users:references'
      expect(validate_rails_command(command)).to include(
        "Reference attribute 'users' should be singular (e.g., 'user')."
      )
    end
  end

  context 'when command has modifier issues' do
    it 'warns if modifiers are not properly formatted' do
      command = 'rails generate model Product price:decimal{10:2}'
      expect(validate_rails_command(command)).to include(
        "Decimal modifier should be {precision,scale}."
      )
    end

    it 'warns if modifiers use incorrect brackets' do
      command = 'rails generate model Product price:decimal[10,2]'
      expect(validate_rails_command(command)).to include(
        "Invalid attribute format 'price:decimal[10,2]'."
      )
    end
  end

  context 'when command has option issues' do
    it 'warns if option is not allowed' do
      command = 'rails generate model User name:string --unknown-option'
      expect(validate_rails_command(command)).to include("Option '--unknown-option' is not allowed.")
    end

    it 'accepts allowed options' do
      command = 'rails generate model User name:string --skip-routes'
      expect(validate_rails_command(command)).to be_empty
    end

    it 'warns if both allowed and disallowed options are used' do
      command = 'rails generate model User name:string --skip-routes --bad-option'
      warnings = validate_rails_command(command)
      expect(warnings).to include("Option '--bad-option' is not allowed.")
      expect(warnings).not_to include("Option '--skip-routes' is not allowed.")
    end
  end

  context 'when command is incomplete or incorrect' do
    it 'warns if no generator type is specified' do
      command = 'rails generate'
      expect(validate_rails_command(command)).to include("No generator type specified.")
    end

    it 'doesnt warn if unknown generator type is specified' do
      command = 'rails generate unknown User'
      expect(validate_rails_command(command)).to be_empty
    end

    it 'warns if no name is specified for the generator' do
      command = 'rails generate model'
      expect(validate_rails_command(command)).to include("No name specified for the generator.")
    end

    it 'warns if attribute has no type' do
      command = 'rails generate model User name'
      expect(validate_rails_command(command)).to include("No type specified for attribute 'name'.")
    end

    it 'warns if attribute format is invalid' do
      command = 'rails generate model User name:string:extra'
      expect(validate_rails_command(command)).to include("Invalid attribute format 'name:string:extra'.")
    end
  end

  context 'when command uses prefixes' do
    it 'accepts command with "bin/rails" prefix' do
      command = 'bin/rails g model User name:string'
      expect(validate_rails_command(command)).to be_empty
    end
  end

  context 'when multiple issues are present' do
    it 'reports all issues found' do
      command = 'rails generate model Users class:str --bad-option'
      warnings = validate_rails_command(command)
      expect(warnings).to include(
        "Model name 'Users' should be singular and in CamelCase (e.g., 'User').",
        "Attribute name 'class' is a reserved word.",
        "Attribute type 'str' is not supported.",
        "Option '--bad-option' is not allowed."
      )
    end
  end

  context 'when controller name matches an existing model' do
    before do
      # Mock Dir.glob to simulate existing model files
      allow(Dir).to receive(:glob).with('app/models/*.rb').and_return(['app/models/user.rb'])
    end

    it 'warns about the name conflict and suggests using plural form' do
      command = 'rails generate controller User index'
      warnings = validate_rails_command(command)
      expect(warnings).to include(
        "Controller name matches an existing model 'User'. Did you want to create a controller for this model? Use plural form 'Users'."
      )
    end

    it 'does not warn when using the pluralized controller name' do
      command = 'rails generate controller Users index'
      warnings = validate_rails_command(command)
      expect(warnings).to be_empty
    end
  end

  context 'when testing migration generator' do
    it 'accepts valid migration command' do
      command = 'rails generate migration AddDetailsToUsers bio:text'
      expect(validate_rails_command(command)).to be_empty
    end

    it 'warns if attribute in migration uses reserved word' do
      command = 'rails generate migration AddDetailsToUsers class:string'
      expect(validate_rails_command(command)).to include("Attribute name 'class' is a reserved word.")
    end
  end

  context 'edge cases' do
    it 'accepts attribute names with capital letters' do
      command = 'rails generate model User Name:string'
      expect(validate_rails_command(command)).to be_empty
    end

    it 'warns if attribute is improperly formatted with missing name' do
      command = 'rails generate model User :string'
      expect(validate_rails_command(command)).to include("Invalid attribute format ':string'.")
    end

  end
end
end