# spec/baker_spec.rb
require 'rspec'
require_relative '../lib/baker'

RSpec.describe Baker do

  def baker_run_no_exit

    expect {
      @baker.run
    }.not_to raise_error

  end

  describe '#process_args' do
    before do
      @baker = Baker.new
    end

    it 'enables verbose mode when -v is passed' do
      stub_const('ARGV', ['-v', "spec/testfiles/bake_nop.md"])
      expect {
        expect { @baker.process_args }.to output(/Verbose mode/).to_stdout
      }.not_to raise_error
      expect(@baker.debug).to be true
    end

    it 'enables interactive mode when -i is passed' do
      stub_const('ARGV', ['-i', "spec/testfiles/bake_nop.md"])
      expect { @baker.process_args }.not_to raise_error
      expect(@baker.interactive).to be true
    end

    it 'sets file_name to the given argument' do
      stub_const('ARGV', ["spec/testfiles/bake_nop.md"])
      expect { @baker.process_args }.not_to raise_error
      expect(@baker.file_name).to eq(File.expand_path('spec/testfiles/bake_nop.md'))
    end

    it 'exits with an unknown option' do
      stub_const('ARGV', ['-x'])
      expect { @baker.process_args }.to raise_error(SystemExit).and output(/invalid option: -x/).to_stdout
    end
  end

  describe 'unindent_common_whitespace' do
    it 'removes common whitespace from the beginning of each line' do
      expect(Baker.new.unindent_common_whitespace("  test\n test2")).to eq(" test\ntest2")
    end
  end

  describe '#run' do
    before do
      @baker = Baker.new
      allow(@baker).to receive(:process_args).and_return(nil)
      allow(File).to receive(:read).and_return("::var[test]")
      allow(@baker).to receive(:save).and_return(nil)
      allow($stdin).to receive(:gets).and_return('testvalue')
      # Ensure TTY::Prompt::new.ask returns 'testvalue'
      allow_any_instance_of(TTY::Prompt).to receive(:ask).and_return('testvalue')
    end

    xit 'processes recipe steps' do
      expect { baker_run_no_exit }.to output(/Please enter your value for variable 'test':/).to_stdout
    end
  end

  describe '#run with cd command' do
    before do
      @baker = Baker.new
      allow(@baker).to receive(:process_args).and_return(nil)
      allow(File).to receive(:read).and_return('::var[app_name]{myapp}'+"\n"+'::cd["~/projects/#{app_name}"]')
      allow(@baker).to receive(:save).and_return(nil)
    end

    it 'processes recipe steps' do
      expect(Dir).to receive(:chdir).with("~/projects/myapp")
      expect{ baker_run_no_exit }.to output(/Changing directory to: ~\/projects\/myapp/).to_stdout
    end
  end

  describe '#run with ruby code' do
    before do
      @baker = Baker.new
      allow(@baker).to receive(:process_args).and_return(nil)
      allow(File).to receive(:read).and_return(' - [ ] Run: ``mytest(1)``')
      allow(@baker).to receive(:save).and_return(nil)
    end
    
    # Define the `mytest` method on Object
    class Object
      def mytest(arg)
        # You can leave this empty or provide a mock implementation
      end

      def mytest2(arg)
        # You can leave this empty or provide a mock implementation
      end
    end

    it 'processes recipe steps' do
      allow_any_instance_of(Object).to receive(:mytest).with(1).and_return(:unused)
      
      expect { baker_run_no_exit }.to output(/Successfully executed/).to_stdout

      expect(@baker.recipe.steps.first.completed?).to eq(true)
    end
  end

  describe '#run with ruby code but relay errors' do
    before do
      @baker = Baker.new
      allow(@baker).to receive(:process_args).and_return(nil)
      allow(File).to receive(:read).and_return(' - [ ] Run: ``mytest2(1)``')
      allow(@baker).to receive(:save).and_return(nil)
    end
    
    it 'processes recipe steps' do
      allow_any_instance_of(Object).to receive(:mytest2).and_raise(StandardError, "Can't mytest2(1)")     
      expect { 
        expect {
          @baker.run
        }.to raise_error(SystemExit)
       }.to output(/Can't mytest2\(1\)/).to_stdout
      expect(@baker.recipe.steps.first.completed?).to eq(false)
    end
  end

end

RSpec.describe Recipe do

  describe '.from_s' do

    it '.from_s to_s round-trip' do

      input = " - [ ] test1\n - [ ] test2"
      recipe = Recipe.from_s(input)

      expect(recipe.to_s).to eq(input)
    end        

    it '.from_s to_s round-trip bigger' do

      input = <<~EOL
      - Enter the app name:
      ::var[APP_NAME]

      - Enter the host name:
      EOL
      expect(Recipe.from_s(input).to_s).to eq(input)
    end    

    it 'creates a Recipe object from a simple var string' do
      recipe = Recipe.from_s("::var[test]{value}")
      
      s1 = recipe.steps.first
      expect(s1.type).to eq(:directive)
      expect(s1.directive_type).to eq(:var)
      expect(s1.content).to eq('test')
      expect(s1.attributes).to eq('value')
    end

    it 'creates a Recipe object from a simple var string with a newline' do
      recipe = Recipe.from_s(<<~EOL
      ::var[test]{value}
      ::var[test2]{}
      ::var[test3]      
      EOL
      )

      recipe.steps.each { |s| 
        expect(s.type).to eq(:directive)
        expect(s.directive_type).to eq(:var)
      }
      
      s1 = recipe.steps.first
      expect(s1.content).to eq('test')
      expect(s1.attributes).to eq('value')

      s2 = recipe.steps[1]
      expect(s2.content).to eq('test2')
      expect(s2.attributes).to eq("")

      s3 = recipe.steps[2]
      expect(s3.content).to eq('test3')
      expect(s3.attributes).to eq(nil)
    end

    it 'creates a Recipe object with completed and incompleted steps' do
      recipe = Recipe.from_s(<<~EOL
      - [ ] `echo 'test'`
      - [x] `echo 'test2'`
      - [ ] with prefix: `echo 'test3'`
      - [x] with prefix: `echo 'test4'`
        - [ ] with indent: `echo 'test5'`
        - [-] with indent: `echo 'test6'`
      EOL
      )

      recipe.steps.each { |s| 
        expect(s.type).to eq(:shell)
      }
      [0, 2, 4].each { |i| expect(recipe.steps[i].completed?).to be false }
      [1, 3, 5].each { |i| expect(recipe.steps[i].completed?).to be true }
    end

    it 'supports basic multi-line ruby commands' do

      input = " - [ ] Insert Flash into application.html.erb: ```1 + 1 == 3\n```"

      recipe = Recipe.from_s input
      
      expect(recipe.steps.size).to eq(1)
      s = recipe.steps.first

      expect(s.type).to eq(:ruby)
      expect(s.command).to eq("1 + 1 == 3\n")
      expect(s.description).to eq("Insert Flash into application.html.erb")
      expect(s.completed?).to be false

      expect(s.to_s).to eq(input)

    end

    it 'supports colon in description and code' do

      input = " - [ ] If a colon : is in the description and in the code: ```puts 'test: test'```"
      recipe = Recipe.from_s input
      
      expect(recipe.steps.size).to eq(1)
      s = recipe.steps.first
      expect(s.description).to eq("If a colon : is in the description and in the code")
      expect(s.command).to eq("puts 'test: test'")

    end

    it 'supports multi-line ruby commands' do

      input = <<~EOL
        - [ ] Insert Flash into application.html.erb: ```inject_into_file "app/views/layouts/application.html.erb", after: "<body>" do
          <<~HTML
            <p class="notice"><%= notice %></p>
            <p class="alert"><%= alert %></p>
          HTML
        end
        ```
        EOL

      recipe = Recipe.from_s input
      
      expect(recipe.steps.size).to eq(1)
      s = recipe.steps.first

      expect(s.type).to eq(:ruby)
      expect(s.command).to eq( <<~RUBY
        inject_into_file "app/views/layouts/application.html.erb", after: "<body>" do
          <<~HTML
            <p class="notice"><%= notice %></p>
            <p class="alert"><%= alert %></p>
          HTML
        end
        RUBY
      )

      expect(s.to_s).to eq(input)

    end

  end

end