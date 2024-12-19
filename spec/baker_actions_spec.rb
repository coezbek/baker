require 'rspec'
require 'tempfile'
require_relative '../lib/baker/bakeractions'

RSpec.describe BakerActions do

  subject { Class.new { include BakerActions }.new }

  def with_tempfile(content)
    Tempfile.create(['test_file', '.rb']) do |file|
      file.write(content)
      file.rewind
      yield file
    end
  end

  it 'inserts new positional and keyword arguments into the file' do
    with_tempfile('devise_for :users') do |file|

      result = nil
      expect {
        result = subject.insert_method_arg_to_file(file.path, :devise_for, :users, :admin, controllers: { omniauth_callbacks: "users/omniauth_callbacks" })
      }.not_to output.to_stdout
      expect(result).to eq(true)
      content = File.read(file.path)
      expect(content).to eq('devise_for :users, :admin, controllers: { omniauth_callbacks: "users/omniauth_callbacks" }')
    end
  end

  it 'returns :true if all arguments already exist' do
    content = 'devise_for :users'
    with_tempfile(content) do |file|
      result = nil
      expect { result = subject.insert_method_arg_to_file(file.path, :devise_for, :users) }.to output(/identical/i).to_stdout      
      expect(result).to eq(true)
      expect(File.read(file.path)).to eq(content)
    end
  end

  it 'returns false if no matching method call is found' do
    with_tempfile('resources :users') do |file|
      
      result = nil
      expect {
        result = subject.insert_method_arg_to_file(file.path, 
          :devise_for, :users, :admin, controllers: { omniauth_callbacks: "users/omniauth_callbacks" })      
      }.to output(/method not found/i).to_stdout 

      expect(result).to eq(false)

      expect(File.read(file.path)).to eq('resources :users')
    end
  end

  it 'returns true if no change is made but prints a warning' do

    input = 'devise_for :users, controllers: { omniauth_callbacks: "users/omniauth_callbacks" }'
    with_tempfile(input) do |file|
      
      result = nil
      expect {
        result = subject.insert_method_arg_to_file(file.path, 
          :devise_for, :users, controllers: { omniauth_callbacks: "users/omniauth_callbacks" })
       
      }.to output(/identical/i).to_stdout 

      expect(result).to eq(true)

      expect(File.read(file.path)).to eq(input)
    end
  end

  it 'handles existing keyword arguments and merges recursively' do
    initial_content = 'devise_for :users, controllers: { registrations: "users/registrations" }'
    expected_content = 'devise_for :users, controllers: { registrations: "users/registrations", omniauth_callbacks: "users/omniauth_callbacks" }'
    with_tempfile(initial_content) do |file|
      result = subject.insert_method_arg_to_file(file.path, :devise_for, :users, controllers: { omniauth_callbacks: "users/omniauth_callbacks" })
      expect(result).to eq(true)
      expect(File.read(file.path)).to eq(expected_content)
    end
  end

  it 'raises an error and returns false for invalid Ruby syntax in the file' do
    with_tempfile('devise_for :users controllers {') do |file|

      result = nil
      expect {
        result = subject.insert_method_arg_to_file(file.path, 
          :devise_for, 
          :users, 
          controllers: { omniauth_callbacks: "users/omniauth_callbacks" })  
        
      }.to output(/invalid syntax/i).to_stdout 

      expect(result).to eq(false)
    end
  end
end
