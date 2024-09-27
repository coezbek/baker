# baker Readme

Baker is a "Project Setup As Code" tool and allows you to specify the steps to setup a project, execute them and track their progress.

Baker is using Markdown syntax to define lists of steps to execute in order to setup a project. The steps can be a combination of shell commands and manual steps.

For example, to setup a basic Rails project, you can create a `bake_rails.md` file with the following content:

```markdown
# Very Basic Rails Project Setup

- [ ] `rails new myapp -j esbuild`
::cd["myapp"]
- [ ] `gh repo create --public --source=.`
- [ ] `echo "# Myapp Readme" >> README.md`
- [ ] `git add .`
- [ ] `git commit -m "rails new myapp"`
- [ ] `git push --set-upstream origin main`
- [ ] `code .`
- [ ] Manually review the generated code
```

You can then use baker to run the steps in the `rails_template.md` file:

```bash
baker rails_template.md
```

This will sequentially execute the shell commands in the file, mark them as done (turning `[ ]` into `[x]`) and prompt you to manually execute the manual steps. You can stop the executation at any time by pressing `Ctrl+C` and resume execution later.

You can find a real-world example of a Rails template in [`templates/rails_template.md`](templates/rails_template.md). This also installs `Devise`, `Picocss` and admin interface, etc.

## Key ideas

- **Tinker style**: Baker is designed to modify the bake-file as you go. When baker runs automated steps for you, it will mark them as done, or prompt you to execute the steps manually and come back to tick them off yourself. Nothing prevents you to modify the bake-file yourself in any editor.

- **Local first**: In contrast to heavy weight automation solutions like [Ansible](), `baker` gives you primarily standard shell commands so you understand what is happening. You don't have to guess if something is a yaml configuration or a command.

- **Imperative**: Baker is imperative programming from the top of the file to the bottom. It explicitely doesn't want to be declarative like [Terraform](). Once a command is executed by baker, you can tinker with the result at will.

- **For humans**: While you might start with an existing template and run it using `baker`, it is easy to continue to use the bake file to document what else you have done manually and what you still need to do.

## Basic features

Baker uses Markdown syntax to include additional directives to control the execution of the script. Directives use the syntax `::name[content]{attribute1=value1, attribute2=value2}`.

The following directives are available:

- `::var[variable name]{value}` - Define a variable that can be used in the shell commands.
  - If value is not provided, baker will prompt the user to enter the value and modify the `md` file to store the value.

- `::cd["directory"]` - Change the current working directory to the specified directory.
  - Note: The `cd` shell command is executed in a sub-shell and can't be used to change the current working directory of `baker`.

- `::template[name]` - Will make a copy of the currently running bake file, remove the `::template` directive and save uner the given name. Use this in generic templates to prevent `baker` from editing the generic template.

## Expanded example:

Example `rails_template.md`:

```markdown
# Rails Template

- Markdown leaf block directive `template` can be used to prevent baker from overwrite generic templates
  - When baker encounters the `template` directive it will copy the template file to the current working directory (`pwd`) and delete the `template` directive.

::template

- Markdown leaf block directive `var` can be used to define variables that can be used in the shell commands
  - When using `baker` these variables are replaced with the values provided by the user 
::var[APP_NAME]

:::ruby
# Markdown Container Block Directives marked with :::ruby are executed as ruby code 
puts APP_NAME
:::

- [ ] Check if directory already exists: `(! [ -d "#{APP_NAME}" ] || (puts "Directory '#{APP_NAME}' already exists" && exit 1) )`
- Setup rails 
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

```

To execute the steps in the `rails_template.md` file, run the following command:

```bash
baker rails_template.md
```

This will execute the file from the top to the bottom, stopping at each todo (based on ` - [ ]`) and then either prompting the user to execute the task manually or executing the shell command. If the shell command fails, the baker will stop and print the error message.

## Common ways to do things

 - Run things inside the rails console: `rails runner 'User.first.add_role(:admin).save!'`
   - Note: Don't use `echo 'User.first.add_role(:admin).save!' | rails c` because `rails console` doesn't return a non-zero exit code when there is an error, but baker would not stop on error.

 - Insert a text before something:
   - Use `sed` to insert before the match: `sed -i '/  # config.before_action do/i\\ \ config.before_action do |controller|\\n    unless !current_user || current_user.has_role?(:admin)\\n      flash[:alert] = "Administrator access required."\\n      redirect_to Trestle.config.root\\n    end\\n  end' config/initializers/trestle.rb`
    - Note the escaped spaces `\ ` at the beginning of the lines to be inserted.
    - You could use `sed -i '/string to be replace/a string to insert' file` to append after the match (notice the `a`). 
   - Or use [methods from Rails Generators](https://guides.rubyonrails.org/generators.html#generator-helper-methods) via `ruby`: `ruby -e 'require "rails/generators";Rails::Generators::Base.new.inject_into_file "config/initializers/trestle.rb", "  config.before_action do |controller|\n    unless !current_user || current_user.has_role?(:admin)\n      flash[:alert] = \\"Administrator access required.\\"\n      redirect_to Trestle.config.root\n    end\n  end\n", before: /  # config.before_action do/'`

## Note on security

Running baker templates is executing shell commands on your machine. Thus, you should always review templates before running them.

## Todo

- [ ] Add interactive mode (`baker -i`) to prompt each step before executing it.
- [ ] Add forced interactive steps `- [ ]?` to prompt the user even if not running in interactive mode.
- [ ] Add steps which are always executed even when rerunning the bake script.
- [ ] Add a way to enable/skip sub-sections (indented todos)
- [ ] Finalize README and add sections for how to install, develop, contribute.

## Related works

How does `baker.rb` compare to...

- [Rails Application Templates](https://guides.rubyonrails.org/rails_application_templates.html) - Rails Application Templates are Ruby files containing DSL for adding gems/initializers/routes etc. to a Rails application. You can run them with `rails new $AppName -m ~/template.rb`. It is easy to use Rails Application Templates in a baker file. Just execute the shell command `rails app:template LOCATION=~/template.rb` in the baker file.
  - You can browse a collection of Rails Application Templates at [RailsBytes](https://railsbytes.com/). 
  - [Rubidium.io Templates](https://www.rubidium.io/) is/was another repoistory of some Rails Applicatoin Templates.

- [Juypter notebooks](): Jupyter notebooks are a great way to document and execute code and re-run sections of said code. It gives you a visual indication of what you have already run and allows you easily to re-run everything from the beginning of the Juypter script again. Baker shares the same tinker style and working from the top but considers the completed tasks done. Bakers idea of copying templates to then edit them as you progress to the steps of the template and modifying the template makes `baker` more versatile to 

- [Literate programming](https://en.wikipedia.org/wiki/Literate_programming): Literate programming allows you to mix 

- [Terraform](): 