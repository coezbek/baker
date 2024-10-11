# Baker

Baker is a "Project Setup as Code" tool that allows you to specify the steps to set up a project, execute them, and track their progress.

Baker uses Markdown syntax to define lists of steps to execute in order to set up a project. The steps can be a combination of shell commands, ruby code and manual steps.

For example, to set up a basic Rails project, you can create a `bake_rails.md` file with the following content:

```markdown
# Very Basic Rails Project Setup

- [ ] `rails new myapp -j esbuild`
::cd["myapp"]
- [ ] Create Github repo privately: `gh repo create --private --source=.`
- [ ] `echo "# Myapp Readme" >> README.md`
- [ ] `git add .`
- [ ] `git commit -m "rails new myapp"`
- [ ] `git push --set-upstream origin main`
- [ ] Start Editor, e.g. VSCode: `code .`
- [ ] Manually review the generated code
```

You can then use Baker to run the steps in this file:

```bash
baker bake_rails.md
```

This will sequentially execute the shell commands in the file, mark them as done (turning `[ ]` into `[x]`), and prompt you to manually execute the manual steps. You can stop the execution at any time by pressing `Ctrl+C` and resume execution later.

You can find a real-world example of a Rails template in [`templates/rails_template.md`](templates/rails_template.md). This also installs `Devise`, `PicoCSS`, an admin interface and deploys using Dokku.

## Installation

To install Baker, run:

```bash
gem install bakerb
```

Then either create your own bake file or use one of the templates in the `templates` directory and run it with:

```bash
baker your_bake_file.md
```

## Key Ideas

- **Tinker Style**: Baker is designed to modify the bake file as you go. When Baker runs automated steps for you, it will mark them as done or prompt you to execute the steps manually and come back to tick them off yourself. Nothing prevents you from modifying the bake file yourself in any editor.

- **Local First**: In contrast to heavyweight automation solutions like [Ansible](https://www.ansible.com/), Baker gives you primarily standard shell commands so you understand what is happening. You don't have to guess if something is a YAML configuration or a command.

- **Imperative**: Baker is imperative programming from the top of the file to the bottom. It explicitly doesn't aim to be declarative like [Terraform](https://www.terraform.io/). Once a command is executed by Baker, you can tinker with the result at will.

- **For Humans**: While you might start with an existing template and run it using Baker, it's easy to continue using the bake file to document what else you have done manually and what you still need to do.

## Basic Features

Baker uses Markdown syntax and includes additional directives to control the execution of the script. Directives use the syntax `::name[content]{attribute1=value1, attribute2=value2}`.

The following directives are available:

- `::var[variable name]{value}`: Define a variable that can be used in the shell commands.
  - If the value is not provided, Baker will prompt the user to enter the value and modify the `md` file to store the value.

- `::cd["directory"]`: Change the current working directory to the specified directory.
  - Note: The `cd` shell command is executed in a subshell and can't be used to change the current working directory of Baker.

- `::template[name]`: Makes a copy of the currently running bake file, removes the `::template` directive, and saves it under the given name. Use this in generic templates to prevent Baker from editing the generic template.
  - The template directive is removed and replaced with the `::template_source` directive, which points to the original template file. You can use this together with command line option `--diff` to see what changes you have made to the original template.

## Variables used by Baker

A minimal set of variables is used by Baker to let you control its behavior:

 - `WRAP_COMMAND`: If set to a non-nil value, Baker will wrap shell commands using the provided string value. Baker will provide the actual shell command as `COMMAND`. For example if `WRAP_COMMAND` is set to `ssh #{DEPLOY_HOST} -t "#{COMMAND.gsub('"', '\"')}"` then Baker will following commands on a remote server. In many situtations you need to escape double quotes. Use `:::var[WRAP_COMMAND]{}` to unset the variable. This could also be used to use another shell than `sh` which Ruby uses: `bash -c "#{COMMAND.gsub('"', '\"')}"`.

 > [!IMPORTANT]
 > The `WRAP_COMMAND` only applies to shell commands and not to Ruby code blocks.
 
## Expanded Example

Example `rails_template.md`:

````markdown
# Rails Template

- Markdown leaf block directive `template` can be used to prevent Baker from overwriting generic templates.
  - When Baker encounters the `template` directive, it will copy the template file to the current working directory (`pwd`) and delete the `template` directive.

::template

- Markdown leaf block directive `var` can be used to define variables that can be used in the shell commands.
  - When using Baker, these variables are replaced with the values provided by the user.

::var[APP_NAME]

- [ ] Codeblocks which start on a line with a ` - ` or ` - [ ] ` are executed as ruby code if they start with three backticks and are after a colon: ```
  puts APP_NAME
  ```

- [ ] Check if directory already exists: `(! [ -d "#{APP_NAME}" ] || (echo "Directory '#{APP_NAME}' already exists" && exit 1))`
- Setup Rails
  - [ ] `rails new #{APP_NAME} -j esbuild`
  - [ ] `cd #{APP_NAME}`
  - [ ] `gh repo create --public --source=.`
  - [ ] `echo "# #{APP_NAME} Readme" >> README.md`
  - [ ] `touch .bash_history`
  - [ ] `git add .`
  - [ ] `git commit -m "rails new #{APP_NAME}"`
  - [ ] `git push --set-upstream origin main`
  - [ ] `code .`
- [ ] Manually review the generated code
````

To execute the steps in the `rails_template.md` file, run the following command:

```bash
baker rails_template.md
```

This will execute the file from the top to the bottom, stopping at each todo (based on `- [ ]`) and then either prompting you to execute the task manually or executing the shell command. If the shell command fails, Baker will stop and print the error message.

## Common Ways to Do Things

- **Escaping**: Use the usual Ruby string escape rules: 
  - Use double quotes for interpolation and single quotes for literals.
  - Use `%Q()` and `%q()` if you don't want to escape double and single quotes and your text has properly balanced braces.
  - Otherwise you can use `%{}`, `%<>`, `%[]` (also ensure that braces are balanced). Or `%+...+` or any other non-alphanumerical symbol.

- **Aborting on Error**: Shell scripts trigger an error by returning a non-zero exit code. Ruby commands either should raise or return false from their last command to trigger an error.

- **Run Commands Inside the Rails Console**: Use `rails runner` instead of piping commands into `rails console`.

  ```bash
  rails runner 'User.first.add_role(:admin).save!'
  ```

  *Note*: Avoid using `echo '...' | rails c` because `rails console` doesn't return a non-zero exit code when there is an error, so Baker would not stop on error.

- **Insert Text Before a Specific Line**:

  - Using `sed` to insert before a match:

    ```bash
    sed -i '/  # config.before_action do/i\\
     \ config.before_action do |controller|\\n    unless !current_user || current_user.has_role?(:admin)\\n      flash[:alert] = "Administrator access required."\\n      redirect_to Trestle.config.root\\n    end\\n  end' config/initializers/trestle.rb
    ```

    *Note*: The escaped spaces `\ ` at the beginning of the lines to be inserted.

  - Using [Rails Generator Methods](https://guides.rubyonrails.org/generators.html#generator-helper-methods):

    ```bash
    ruby -e 'require "rails/generators"; Rails::Generators::Base.new.inject_into_file "config/initializers/trestle.rb", "  config.before_action do |controller|\n    unless !current_user || current_user.has_role?(:admin)\n      flash[:alert] = \\"Administrator access required.\\"\n      redirect_to Trestle.config.root\n    end\n  end\n", before: /  # config.before_action do/'
    ```
      - Note: The Rails Generator Method/Action are included in scope of the triple backtick Ruby code blocks for convenience.
      - Note: The Rails Generator Methods do not return errors in many situations, but just print red text! Beware!

## Workflow when developing your own templates

While creating templates to reuse for your own projects, you will usually start with a generic template (i.e. `template.md`) and then instantiate it for a specific project (i.e. `my_project.md`). By using the `::template` directive, this is easy.

You will then continue to work with the specific instance and likely find many things which are applicable to the generic template.

To merge your changes back, you can use run `baker --diff my_project.md > patch template.md`. This will read your `my_project` file and for the purpose of comparing mark the todos as unfinished (`[ ]`) and write a normal `git diff` to stdout. 

## Note on Security

Running Baker templates involves executing shell commands on your machine. Always review templates before running them to ensure they are safe.

## TODO

- [ ] Add forced interactive steps `- [?]` to prompt the user even if not running in interactive mode.
- [ ] Add steps that are always executed, even when rerunning the bake script.
- [ ] Add a way to enable/skip subsections (indented todos).
- [ ] Finalize README and add sections on how to install, develop, and contribute.
- [ ] Integrate `https://www.shellcheck.net/` to check shell commands for common mistakes before running them.

## Changelog

### Unreleased

- Output line numbers in the bake file when an error occurs, so you can easily jump to the offending task (incl. when interpolating)
- Introduce WRAP_COMMAND to allow wrapping shell commands in a custom command (e.g. `ssh -t`)
- Add support for '-f', '--fast-forward' to printing of completed steps.
- Add interactive mode (`baker -i`) to prompt each step before executing it.
- Highlight all trailing whitespaces in bakefiles (in particular due to HEREDOC)
- Markdown blocks starting on newlines are supported (' - [] description:\n```your code incl. newlines```).
- Add '--no-save' option to run bake file without saving completed tasks.
- Added a small plugin system to extend Baker's functionality.

### 0.1.0
- Support running colorized/animated shell commands.
- Support for diff mode (`-d, --diff`) to show the diff between the current bake file and the original template file.
- Prevent overwriting a manually edited bake file.
- Add support for the `::templateSource` directive.

## Command line options

```
baker [options] [file]
```

Options:
- `-v`, `--verbose`: Print more information about what Baker is doing.
- `-d`, `--diff`: Show the diff between the current bake file and the original template file.
- `-i`, `--interactive`: Prompt before executing each step.
- `-f`, `--fast-forward`: Don't print completed steps again
- `--no-save`: Don't save any changes to the bake file. CAUTION: Tasks will still be run!

## Extending Baker

Baker includes a small plugin system that allows to hook into some aspects of the execution of the bakefile.

To create a plugin, create a Ruby file in the `plugins` directory and register a block for actions that you are interested in:

```ruby
# The following triggers/hook types are availabe:
#
#  :before_load, :after_load           - before/after the baker file is loaded
#  :before_line                        - before the line is undergoing variable expansion. Will be called even for lines which are completed ([x])
#  :before_expansion, :after_expansion - before/after the line is undergoing variable expansion.
#  :before_execution, :after_execution - before/after the line is executed
#  :before_save, :after_save           - before/after the baker file is saved (which happens after each line with a task/command)
#  :all  
Baker.plugins.register(:trigger) do

end
```

See the [`baker/plugins.rb`](baker/plugins.rb) for more details.

As an example see the [`lib/baker/plugins/rails_generate_preflight.rb`](lib/baker/plugins/rails_generate_preflight.rb) plugin that checks if a Rails generator command contains any common mistakes.

## Related Works

**How does `baker.rb` compare to...**

- **[Rails Application Templates](https://guides.rubyonrails.org/rails_application_templates.html)**: Rails Application Templates are Ruby files containing DSL for adding gems, initializers, routes, etc., to a Rails application. You can run them with `rails new $AppName -m ~/template.rb`. It's easy to use Rails Application Templates in a Baker file by executing the shell command `rails app:template LOCATION=~/template.rb`.
  - Browse a collection of Rails Application Templates at [RailsBytes](https://railsbytes.com/).
  - [Rubidium.io Templates](https://www.rubidium.io/) is/was another repoistory of some Rails Applicatoin Templates.

- **[Boring Generators](https://github.com/abhaynikam/boring_generators)**: Boring Generators is a great collection of Rails generators that can be used to generate boilerplate code for Rails applications. After installing with `gem install boring_generators` you can use the shell command `boring g boring:xxx:install` to run any of their generators in a Baker file. Their generators are well thought out and can simplify bake scripts.

- **[Jupyter Notebooks](https://jupyter.org/)**: Jupyter notebooks are excellent for documenting and executing code. They provide visual indications of executed code and allow easy re-execution from the beginning. Baker shares the same tinker style but treats completed tasks as done, making it more versatile for project setups.

- **[Literate Programming](https://en.wikipedia.org/wiki/Literate_programming)**: Literate programming allows mixing code and documentation in a single file. Baker adopts a similar approach but is focused on executing setup steps.

- **[Terraform](https://www.terraform.io/)**: Terraform is a tool for building, changing, and versioning infrastructure safely and efficiently. Unlike Terraform's declarative approach, Baker is imperative, executing commands from top to bottom.
