# spec/recipe_parser_spec.rb

require 'rspec'
require_relative '../lib/baker'  # Adjust the path if necessary

RSpec.describe 'Recipe Parser' do
  describe 'Ruby code block parsing' do
    it 'parses basic inline ruby code block' do
      input = <<~MARKDOWN
        - [ ] Task with inline code:
        ```
        puts 'Hello, world!'
        ```
      MARKDOWN

      recipe = Recipe.from_s(input)
      expect(recipe.steps.size).to eq(1)

      step = recipe.steps.first
      expect(step.type).to eq(:ruby)
      expect(step.description.strip).to eq('Task with inline code')
      expect(step.command.strip).to eq("puts 'Hello, world!'")
      expect(step.task_marker).to eq(' ')
    end

    it 'parses code block starting on next line after colon' do
      input = <<~MARKDOWN
        - [ ] Task with code block starting on next line:
        ```
        def greet(name)
          puts "Hello, \#{name}!"
        end
        ```
      MARKDOWN

      recipe = Recipe.from_s(input)
      expect(recipe.steps.size).to eq(1)

      step = recipe.steps.first
      expect(step.type).to eq(:ruby)
      expect(step.description.strip).to eq('Task with code block starting on next line')
      expect(step.command.strip).to eq(<<~CODE.strip)
        def greet(name)
          puts "Hello, \#{name}!"
        end
      CODE
      expect(step.task_marker).to eq(' ')
    end

    it 'parses code block with closing backticks not at end of line' do
      input = <<~MARKDOWN
        - [ ] Task with code block and trailing text:
        ```
        array = [1, 2, 3]
        array.each do |num|
          puts num
        end
        ```
        Additional notes after code block.
      MARKDOWN

      recipe = Recipe.from_s(input)
      expect(recipe.steps.size).to eq(2)

      step = recipe.steps.first
      expect(step.type).to eq(:ruby)
      expect(step.description.strip).to eq('Task with code block and trailing text')
      expect(step.command.strip).to eq(<<~CODE.strip)
        array = [1, 2, 3]
        array.each do |num|
          puts num
        end
      CODE

      additional_step = recipe.steps.last
      expect(additional_step.type).to eq(:nop) # Assuming additional text is treated as :nop
    end

    it 'parses code block with nested triple backticks in comments' do
      input = <<~MARKDOWN
        - [ ] Task with nested backticks in comments:
        ```
        # This is a method that does something
        def do_something
          # Triple backticks: ```
          puts 'Doing something'
        end
        ```
      MARKDOWN

      recipe = Recipe.from_s(input)
      expect(recipe.steps.size).to eq(1)

      step = recipe.steps.first
      expect(step.type).to eq(:ruby)
      expect(step.description.strip).to eq('Task with nested backticks in comments')
      expect(step.command.strip).to eq(<<~CODE.strip)
        # This is a method that does something
        def do_something
          # Triple backticks: ```
          puts 'Doing something'
        end
      CODE
    end

    it 'handles missing closing triple backticks' do
      input = <<~MARKDOWN
        - [ ] Task with missing closing backticks:
        ```
        def incomplete_method
          puts 'This method lacks a proper end'
      MARKDOWN

      expect {
        Recipe.from_s(input)
      }.to raise_error(RuntimeError) # Assuming parser raises an error
    end

    it 'parses code block with extra closing backticks' do
      input = <<~MARKDOWN
        - [ ] Task with extra closing backticks:
        ```
        def example
          puts 'Extra backticks ahead'
        end
        ```
        ```
        ```
      MARKDOWN

      recipe = Recipe.from_s(input)
      expect(recipe.steps.size).to eq(3)

      step = recipe.steps.first
      expect(step.type).to eq(:ruby)
      expect(step.command.strip).to eq(<<~CODE.strip)
        def example
          puts 'Extra backticks ahead'
        end
      CODE

      expect(recipe.steps[1].type).to eq(:nop) # Assuming extra backticks are treated as :nop
      expect(recipe.steps[2].type).to eq(:nop) # Assuming extra backticks are treated as :nop
    end

    it 'parses empty code block' do
      input = <<~MARKDOWN
        - [ ] Task with empty code block:
        ```
        ```
      MARKDOWN

      recipe = Recipe.from_s(input)
      expect(recipe.steps.size).to eq(1)

      step = recipe.steps.first
      expect(step.type).to eq(:ruby)
      expect(step.command.strip).to eq('')
    end

    it 'parses multiple code blocks in one task' do
      input = <<~MARKDOWN
        - [ ] Task with multiple code blocks:
        ```
        def first_method
          puts 'First'
        end
        ```
        - Some explanatory text, but not a task:
        ```
        def second_method
          puts 'Second'
        end
        ```
      MARKDOWN

      recipe = Recipe.from_s(input)
      expect(recipe.steps.size).to eq(7)

      step1 = recipe.steps[0]
      expect(step1.type).to eq(:ruby)
      expect(step1.command.strip).to eq(<<~CODE.strip)
        def first_method
          puts 'First'
        end
      CODE

      [1,2,3,4,5,6].each do |i|
        expect(recipe.steps[i].type).to eq(:nop) # Assuming intermediate text is treated as :nop
      end
    end

    it 'parses code block with additional text after closing backticks' do
      input = <<~MARKDOWN
        - [ ] Task with text after code block:
        ```
        def hello_world
          puts 'Hello, world!'
        end
        ```
        This text should not be part of the code.
      MARKDOWN

      recipe = Recipe.from_s(input)
      expect(recipe.steps.size).to eq(2)

      step = recipe.steps.first
      expect(step.type).to eq(:ruby)
      expect(step.command.strip).to eq(<<~CODE.strip)
        def hello_world
          puts 'Hello, world!'
        end
      CODE

      additional_step = recipe.steps.last
      expect(additional_step.type).to eq(:nop) # Assuming additional text is treated as :nop
    end

    it 'parses a nop correctly' do
      input = "# Rails 7 Template with Devise"
      recipe = Recipe.from_s(input)
      expect(recipe.steps.size).to eq(1)
      expect(recipe.steps.first.type).to eq(:nop)
      expect(recipe.steps.first.description).to eq(input)    
    end

    it 'parses a manual task correctly' do
      input = <<~MARKDOWN
        - [x] Manually review the generated code
        - [ ] This also!!
      MARKDOWN
      recipe = Recipe.from_s(input)
      expect(recipe.steps.size).to eq(2)
      expect(recipe.steps[0].type).to eq(:manual)
      expect(recipe.steps[0].description).to eq('Manually review the generated code')
      expect(recipe.steps[0].completed?).to be true
      expect(recipe.steps[1].type).to eq(:manual)
      expect(recipe.steps[1].description).to eq('This also!!')
      expect(recipe.steps[1].completed?).to be false
    end

    it 'parses task with indented code block' do
      input = <<~MARKDOWN
        - [ ] Task with indented code block:
            ```
            class Greeter
              def greet
                puts 'Hello!'
              end
            end
            ```
      MARKDOWN

      recipe = Recipe.from_s(input)
      expect(recipe.steps.size).to eq(1)

      step = recipe.steps.first
      expect(step.type).to eq(:ruby)
      expect(step.description.strip).to eq('Task with indented code block')
      expect(step.command).to eq(<<~CODE.indent(4))
        class Greeter
          def greet
            puts 'Hello!'
          end
        end
      CODE
    end

    it 'parses real world' do
      input = <<~'MARKDOWN'
        - [x] Make Docker build less noisy: ``gsub_file "Dockerfile", /apt-get update -qq/,  'apt-get -qq update'``
        - [ ] Add app.json to include health-checks for Rails (db:migration is part of the Dockerfile): ```create_file "app.json", <<~JSON
            {
              "name": "#{APP_NAME}",
              "healthchecks": {
                "web": [
                  {
                      "type": "startup",
                      "name": "#{APP_NAME} /up check",
                      "path": "/up"
                  }
                ]
              }
            }
            JSON
            ```
        - [ ] `bundle exec rubocop -a`
      MARKDOWN
      recipe = Recipe.from_s(input)
      expect(recipe.steps.size).to eq(3)

      step = recipe.steps.first
      expect(step.type).to eq(:ruby)

      step = recipe.steps[1]
      expect(step.type).to eq(:ruby)

      step = recipe.steps[2]
      expect(step.type).to eq(:shell)     
    end

  end
end
