require 'rspec'
require_relative '../lib/baker/insert_method_arg' # Adjust this require to your new file name if needed

RSpec.describe "insert_method_arg" do
  let(:method_name) { :devise_for }
  let(:required_argument) { :users }

  context "when there is a simple devise_for :users without a hash" do
    let(:input_code) do
      <<~RUBY
        Rails.application.routes.draw do
          devise_for :users
        end
      RUBY
    end

    let(:controllers_hash) { { controllers: { omniauth_callbacks: "users/omniauth_callbacks" } } }

    it "adds the controllers hash with omniauth_callbacks" do
      result = insert_method_arg(input_code, method_name, required_argument, **controllers_hash)
      expect(result).to include('devise_for :users, controllers: { omniauth_callbacks: "users/omniauth_callbacks" }')
    end
  end

  context "when there is already a controllers hash without omniauth_callbacks" do
    let(:input_code) do
      <<~RUBY
        Rails.application.routes.draw do
          devise_for :users, controllers: { registrations: "users/registrations" }
        end
      RUBY
    end

    let(:controllers_hash) { { controllers: { omniauth_callbacks: "users/omniauth_callbacks" } } }

    it "adds omniauth_callbacks to the existing controllers hash" do
      result = insert_method_arg(input_code, method_name, required_argument, **controllers_hash)
      expect(result).to include('controllers: { registrations: "users/registrations", omniauth_callbacks: "users/omniauth_callbacks" }')
    end
  end

  context "when controllers hash and omniauth_callbacks already exist" do
    let(:input_code) do
      <<~RUBY
        Rails.application.routes.draw do
          devise_for :users, controllers: { omniauth_callbacks: "users/omniauth_callbacks", registrations: "users/registrations" }
        end
      RUBY
    end

    let(:controllers_hash) { { controllers: { omniauth_callbacks: "users/omniauth_callbacks" } } }

    it "does not duplicate the key" do
      result = insert_method_arg(input_code, method_name, required_argument, **controllers_hash)
      # Should remain unchanged
      expect(result).to eq(input_code)
    end
  end

  context "when adding a different parameter" do
    let(:param_to_add) { { foo: "bar" } }
    let(:input_code) do
      <<~RUBY
        Rails.application.routes.draw do
          devise_for :users
        end
      RUBY
    end

    it "adds the new parameter hash" do
      result = insert_method_arg(input_code, method_name, required_argument, **param_to_add)
      expect(result).to include('devise_for :users, foo: "bar"')
    end
  end

  context "skips other parameters" do
    let(:param_to_add) { { controllers: { passwords: "users/passwords" } } }
    let(:input_code) do
      <<~RUBY
        Rails.application.routes.draw do
          devise_for :users, class_name: 'Account', controllers: { registrations: "users/registrations" }
        end
      RUBY
    end

    it "merges in the new hash key under controllers" do
      result = insert_method_arg(input_code, method_name, required_argument, **param_to_add)
      expect(result).to include('controllers: { registrations: "users/registrations", passwords: "users/passwords" }')
    end
  end

  context "when extending an existing hash key with another hash" do
    let(:param_to_add) { { controllers: { passwords: "users/passwords" } } }
    let(:input_code) do
      <<~RUBY
        Rails.application.routes.draw do
          devise_for :users, controllers: { registrations: "users/registrations" }
        end
      RUBY
    end

    it "merges in the new hash key under controllers" do
      result = insert_method_arg(input_code, method_name, required_argument, **param_to_add)
      expect(result).to include('controllers: { registrations: "users/registrations", passwords: "users/passwords" }')
    end
  end

  context "when just passing a symbol :controllers" do
    let(:param_to_add) { { controllers: { passwords: "users/passwords" } } }
    let(:input_code) do
      <<~RUBY
        Rails.application.routes.draw do
          devise_for :users, controllers: {}
        end
      RUBY
    end

    it "merges in the new hash key under controllers" do
      result = insert_method_arg(input_code, method_name, required_argument, **param_to_add)
      # Note: This might slightly differ in spacing because we simplified the logic.
      # If needed, adjust arg_to_source formatting in the main code.
      expect(result).to include('controllers: { passwords: "users/passwords" }')
    end
  end

  context "simple positional arguments" do
    it "adds a single positional arg to a method with no args" do
      code = <<~RUBY
        def setup
          do_something
        end
      RUBY

      result = insert_method_arg(code, :do_something, :arg1)
      expect(result).to include("do_something :arg1")
    end

    it "adds multiple positional args to a method with existing args" do
      code = <<~RUBY
        def setup
          do_something :already
        end
      RUBY

      result = insert_method_arg(code, :do_something, :new_arg, :another_arg)
      # Should end up with: do_something :already, :new_arg, :another_arg
      expect(result).to include("do_something :already, :new_arg, :another_arg")
    end

    it "does not duplicate existing positional args" do
      code = <<~RUBY
        def setup
          do_something :existing
        end
      RUBY

      result = insert_method_arg(code, :do_something, :existing)
      # No change expected
      expect(result).to eq(code)
    end
  end

  context "keyword arguments" do
    it "adds a simple keyword arg to a method with no args" do
      code = <<~RUBY
        Rails.application.routes.draw do
          devise_for :users
        end
      RUBY

      result = insert_method_arg(code, :devise_for, :users, foo: "bar")
      # Should end up with: devise_for :users, foo: "bar"
      expect(result).to include('devise_for :users, foo: "bar"')
    end

    it "adds multiple keyword args to a method with existing positional args" do
      code = <<~RUBY
        def configure
          set_config :mode
        end
      RUBY

      result = insert_method_arg(code, :set_config, :mode, verbose: true, timeout: 30)
      # Should end up with: set_config :mode, verbose: true, timeout: 30
      expect(result).to include("set_config :mode, verbose: true, timeout: 30")
    end

    it "does not duplicate existing keyword args if they match exactly" do
      code = <<~RUBY
        def configure
          set_config :mode, verbose: true
        end
      RUBY

      result = insert_method_arg(code, :set_config, :mode, verbose: true)
      # No change
      expect(result).to eq(code)
    end
  end

  context "merging into existing keyword hashes" do
    it "merges new keys into an existing keyword hash" do
      code = <<~RUBY
        Rails.application.routes.draw do
          devise_for :users, controllers: { registrations: "users/registrations" }
        end
      RUBY

      # Insert a new key into controllers hash
      result = insert_method_arg(code, :devise_for, :users, controllers: { omniauth_callbacks: "users/omniauth_callbacks" })

      expect(result).to include('controllers: { registrations: "users/registrations", omniauth_callbacks: "users/omniauth_callbacks" }')
    end

    it "recursively merges into nested hashes" do
      code = <<~RUBY
        Rails.application.routes.draw do
          devise_for :users, controllers: { nested: { a: "x" } }
        end
      RUBY

      # Insert another key into the nested hash
      result = insert_method_arg(code, :devise_for, :users, controllers: { nested: { b: "y" } })

      # Should become: controllers: { nested: { a: "x", b: "y" } }
      expect(result).to include('controllers: { nested: { a: "x", b: "y" } }')
    end

    it "raises an error if trying to merge incompatible values" do
      code = <<~RUBY
        Rails.application.routes.draw do
          devise_for :users, class_name: "Account"
        end
      RUBY

      # Trying to merge controllers: { ... } when controllers doesn't exist. That's fine.
      # Trying to merge a key that exists but is not a hash and not equal would raise an error
      # For demonstration, assume we try to merge a different class_name:
      expect {
        insert_method_arg(code, :devise_for, :users, class_name: "DifferentAccount")
      }.to raise_error(/Don't know how to merge existing value/)
    end
  end

  context "using different method_selector forms" do
    it "works with a string method_selector" do
      code = <<~RUBY
        do_something
      RUBY

      result = insert_method_arg(code, "do_something", test: 123)
      expect(result).to include("do_something test: 123")
    end

    it "works with a node pattern method_selector" do
      pattern = RuboCop::NodePattern.new('(send nil? :do_something ...)')

      code = <<~RUBY
        do_something :already
      RUBY

      result = insert_method_arg(code, pattern, extra: "value")
      expect(result).to include('do_something :already, extra: "value"')
    end

    it "works with a pattern string starting with '('" do
      pattern_str = '(send nil? :do_something ...)'
      code = <<~RUBY
        do_something
      RUBY

      result = insert_method_arg(code, pattern_str, :arg, key: "val")
      expect(result).to include('do_something :arg, key: "val"')
    end

    it "works with a pattern string starting with '('" do
      pattern_str = '(send nil? :do_something ...)'
      code = <<~RUBY
        do_something :arg
      RUBY

      result = insert_method_arg(code, pattern_str, :arg2, key: "val")
      expect(result).to include('do_something :arg, :arg2, key: "val"')
    end
  end

  it "raises if pattern doesn't match due to different arguments" do
    code = <<~RUBY
      Rails.application.routes.draw do
        devise_for :admins
      end
    RUBY
  
    # Pattern expects (sym :users), but we have :admins
    expect {
      result = insert_method_arg(code, '(send nil? :devise_for (sym :users) ...)', controllers: { omniauth_callbacks: "users/omniauth_callbacks" })
    }.to raise_error(/Method not found /)
  end
  
  it "raises if pattern doesn't allow extra arguments" do
    code = <<~RUBY
      Rails.application.routes.draw do
        devise_for :users, controllers: { something: "exists" }
      end
    RUBY
  
    # Pattern expects exactly (send nil? :devise_for (sym :users)) with no `...`, 
    # but code has extra arguments (the controllers hash), so it won't match.

    expect {
      result = insert_method_arg(code, '(send nil? :devise_for (sym :users))', controllers: { omniauth_callbacks: "users/omniauth_callbacks" })
    }.to raise_error(/Method not found /)
  end

  context 'when merging hash keywords recursively' do
    it 'raises an error on conflicting values' do
      code = "foo(bar: { baz: 1 })"
      method_selector = :foo
      keywords = { bar: { qux: 2 } }

      output = insert_method_arg(code, method_selector, **keywords)
      expect(output.strip).to eq("foo(bar: { baz: 1, qux: 2 })")
    end
  end

  context 'when handling trailing spaces' do
    it 'removes unnecessary trailing spaces correctly' do
      code = "foo(bar: :baz) "
      method_selector = :foo
      positionals = [:qux]

      output = insert_method_arg(code, method_selector, *positionals)
      expect(output.strip).to eq("foo(bar: :baz, :qux)")
    end
  end

  context 'when adding existing positional arguments' do
    it 'does not duplicate existing positional arguments' do
      code = "foo(:qux)"
      method_selector = :foo
      positionals = [:qux]

      output = insert_method_arg(code, method_selector, *positionals)
      expect(output.strip).to eq("foo(:qux)")
    end
  end

  context 'when matching complex node patterns' do
    it 'matches and processes nodes with a complex pattern' do
      code = "foo(:qux)"
      method_selector = "(send nil? :foo ...)"
      positionals = [:bar]

      output = insert_method_arg(code, method_selector, *positionals)
      expect(output.strip).to eq("foo(:qux, :bar)")
    end
  end
end