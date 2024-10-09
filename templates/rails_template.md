# Rails 7 Template with Devise

- Enter the app name:
::var[APP_NAME]

- Enter the host name:
::var[HOST_NAME]{default="#{APP_NAME}.com"}

- Enter the from email for devise and action mailer:
::var[FROM_EMAIL]{default="no-reply@#{HOST_NAME}"}

::template["baker_#{APP_NAME}.md"]

- [ ] Check if directory already exists: `(! [ -d "#{APP_NAME}" ] || (echo "Directory '#{APP_NAME}' already exists" && exit 1) )`
- Setup rails
  - [ ] `rails new #{APP_NAME} -j esbuild`
::cd["#{APP_NAME}"]
  - [ ] Create Github Repo privately: `gh repo create --private --source=.`
  - [ ] `echo "# #{APP_NAME} Readme" >> README.md`
  - [ ] `rails db:migrate`
  - [ ] `git add .`
  - [ ] `git commit -m "rails new #{APP_NAME}"`
  - [ ] `git push --set-upstream origin main`

- Configure email defaults:
  - [ ] `ruby -pi -e 'gsub(/from@example.com/, "#{FROM_EMAIL}")' app/mailers/application_mailer.rb`
  - [ ] `git add *.rb && git commit -m "Configure email defaults" && git push`

- Maintain a bash history of locally executed commands, add to .gitignore
  - [ ] `touch .bash_history`
  - [ ] `echo ".bash_history" >> .gitignore`

- Add devise
  - [ ] `bundle add devise`
  - [ ] `rails generate devise:install`
  - [ ] `rails generate devise User`
  - [ ] `rails db:migrate`
  - [ ] `rails generate controller Home index --skip-routes`
  - [ ] Secure all controllers: `ruby -pi -e 'gsub(/end/, "\n  before_action :authenticate_user!\nend")' app/controllers/application_controller.rb`
  - [ ] Except home controller: `ruby -pi -e 'gsub(/^end/, "\n  skip_before_action :authenticate_user!, only: :index\nend")' app/controllers/home_controller.rb`
  - [ ] Insert the flash into application.html.erb: ```inject_into_file "app/views/layouts/application.html.erb", after: "<body>\n" do
          <<~HTML.indent(4)
            <p class="notice"><%= notice %></p>
            <p class="alert"><%= alert %></p>
          HTML
        end
        ```
    - Alternatives Add alert and notice: `ruby -pi -e 'gsub(/<body>/, %q[<body>\n    <p class="notice"><%= notice %></p>\n    <p class="alert"><%= alert %></p>])' app/views/layouts/application.html.erb`
  - [ ] Add root "home#index" in routes.rb: `ruby -pi -e 'gsub(/# root "posts#index"/, %q[root \"home#index\"])' config/routes.rb`
  - [ ] `ruby -pi -e 'gsub(/please.*@example.com/, "#{FROM_EMAIL}")' config/initializers/devise.rb`
  - [ ] Fix fixtures: ```gsub_file "test/fixtures/users.yml", /one: {}\n# column: value\n#\ntwo: {}\n# column: value/, <<~YAML
        one:
          email: "user_one@example.com"
          encrypted_password: <%= Devise::Encryptor.digest(User, 'password123') %>
          remember_created_at: <%= 2.days.ago %>
          reset_password_sent_at: <%= 3.days.ago %>
          reset_password_token: "<reset_token_hash_one>"
          created_at: <%= 30.days.ago %>
          updated_at: <%= Time.zone.now %>

        two:
          email: "user_two@example.com"
          encrypted_password: <%= Devise::Encryptor.digest(User, 'password456') %>
          remember_created_at: <%= 5.days.ago %>
          reset_password_sent_at: <%= 6.days.ago %>
          reset_password_token: "<reset_token_hash_two>"
          created_at: <%= 60.days.ago %>
          updated_at: <%= Time.zone.now %>
        YAML
      ```
  - [ ] `rake test`
  - [ ] `exec rubocop -a`
  - [ ] `git add . && git commit -m "Add devise" && git push`

  - [ ] Start Visual Studio: `code .`
    - [ ] Manually review the generated code

  - Add Picocss
    - [ ] `yarn add @picocss/pico`
    - [ ] `echo '\n// Use Picocss\nimport "@picocss/pico"' >> app/javascript/application.js`
    - Update application.css to accommodate esbuild creating application.css now:
      - [ ] Move application.css out of the way to prevent conflict with esbuild: `mv app/assets/stylesheets/application.css app/assets/stylesheets/application2.css`
      - [ ] Link application2.css from application.html.erb: ``inject_into_file "app/views/layouts/application.html.erb", %(    <%= stylesheet_link_tag "application2", "data-turbo-track": "reload" %>\n), after: %Q(<%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>\n)``
    - [ ] Append Custom Picocss CSS import to `application.js`: ``append_to_file "app/javascript/application.js", 'import "../assets/stylesheets/picocss.css"'``
    - [ ] Create `app/assets/stylesheets/picocss.css` with custom CSS for alerts: ```create_file "app/assets/stylesheets/picocss.css", <<~CSS
        /**
        * Custom PicoCSS styles here. Included via app/javascript/application.js
        */ 
        :root {
          --pico-green-50: #e8f5e9;
          --pico-green-800: #1b5e20;
          --pico-red-50: #ffebee;
          --pico-red-900: #b71c1c;
          --pico-blue-50: #cce5ff;
          --pico-blue-900: #004085;
        }

        /* Alerts base style */
        .alert {
          --pico-iconsize: calc(1.5em); /* icon size */
          margin-bottom: var(--pico-spacing); /* space below alert element */
          padding: var(--pico-form-element-spacing-vertical) var(--pico-form-element-spacing-horizontal); /* same padding as form inputs */
          border-radius: var(--pico-border-radius);
          color: var(--pico-color); /* dynamic color based on context */
          background-color: var(--pico-background-color); /* dynamic background based on context */
          border: 1px solid var(--pico-background-color); /* to match the background color */

          /* icon */
          background-image: var(--pico-icon);
          background-position: center left var(--pico-form-element-spacing-vertical);
          background-size: var(--pico-iconsize) auto;
          padding-left: calc(var(--pico-form-element-spacing-vertical) * 2 + var(--pico-iconsize)); /* Use vertical padding also for left+right */
        }

        .alert-danger, .alert-alert {
          --pico-background-color: var(--pico-red-50);
          --pico-icon: var(--pico-icon-invalid);
          --pico-color: var(--pico-red-900);
        }

        .alert-primary, .alert-notice {
          --pico-background-color: var(--pico-blue-50);
          --pico-icon: var(--pico-icon-valid);
          --pico-color: var(--pico-blue-900);
        }

        .alert-success {
          --pico-background-color: var(--pico-green-50);
          --pico-icon: var(--pico-icon-valid);
          --pico-color: var(--pico-green-800);
        }
      CSS
      ```
    - Wrap body content in a main container:
      - [ ] `ruby -pi -e 'gsub(/<body>/, %q[<body>\n    <main class="container">])' app/views/layouts/application.html.erb`
      - [ ] `ruby -pi -e 'gsub(/<\\/body>/, %q[  <\/main>\n  <\/body>])' app/views/layouts/application.html.erb`
    - [ ] Add partial for flash messages: ```create_file "app/views/application/_flash.html.erb", <<~ERB
            <% # Render with: render partial: "error", locals: { error_key: ..., errors_to_print: ... }
              errors_to_print = Array(errors_to_print)
              if errors_to_print.any? 
            %>
              <div id="<%= error_key %>_explanation">
                <% errors_to_print.each do |message| %>
                <p>
                  <%= simple_format(message, wrapper_tag: "div", class: "alert alert-\#{error_key}") %>
                </p>
                <% end %>
              </div>
            <% end %>
          ERB
      ```
    - [ ] Replace flash messages in `application.html.erb`:```
      gsub_file "app/views/layouts/application.html.erb", 
        %r{    <p class="notice"><%= notice %></p>\s*<p class="alert"><%= alert %></p>\n    <%= yield %>\n}, 
        <<~ERB.indent(6)
          <% if flash.any? %>
            <% flash.each do |key, value| %>
              <%= render partial: "flash", locals: { error_key: key, errors_to_print: value } %>
            <% end %>
          <% end %>
          <%= yield %>
        ERB
      ```
    - [ ] Insert navigation header after `<body>`:```
          inject_into_file "app/views/layouts/application.html.erb", after: "<body>\n" do
            <<~HTML.indent(4)
              <header class="container">
                <nav>
                  <ul>
                    <li><strong><%= link_to "#{APP_NAME.capitalize}", root_path %></strong></li>
                  </ul>
                  <ul>
                    <li><a href="#" class="secondary">Services</a></li>
                    <li>
                      <details class="dropdown">
                      <% if current_user %>
                        <summary>
                          <%= current_user.email %>
                        </summary>
                        <ul dir="rtl">
                          <li><a href="#">Profile</a></li>
                          <li><%= link_to "Logout", destroy_user_session_path, data: { turbo_method: :delete } %></li>
                        </ul>
                      <% else %>
                        <summary>
                          Login
                        </summary>
                        <ul dir="rtl">
                          <li><%= link_to "Login", new_user_session_path %></li>
                          <li><%= link_to "Sign up", new_user_registration_path %></li>
                        </ul>
                      <% end %>
                      </details>
                    </li>
                  </ul>
                </nav>
              </header>
            HTML
          end
          ```
    - [ ] Insert footer: ```
          inject_into_file "app/views/layouts/application.html.erb", before: "  </body>" do
            <<~HTML.indent(4)
              <footer class="container">
                <p><%= year_of_launch = #{Time.now.year}; year_of_launch == Time.now.year ? "" : "\#{year_of_launch} -"%><%= Time.now.year %> #{APP_NAME.capitalize}©</p>
              </footer>
            HTML
          end
          ```
    - [ ] `exec rubocop -a`
    - [ ] `git add . && git commit -m "Add Picocss" && git push`

  - [ ] Add Basic Database Classes for your app below
    - Either use `generate model` or `generate scaffold`
    - Field names should not include: `type`, `id`, (`hash` or other existing ruby object method names), `created_at|on`, `updated_at|on`, `deleted_at`, `lock_version`, `position`, `parent_id`, `lft`, `rgt`, `quote_value`
    - Use the following types for the fields:
      - string
      - text
      - integer
      - float
      - decimal{6,2} - Prefer over float for currency/accurate numbers
      - datetime
      - boolean
      - references
    - [ ] `rails generate scaffold Event name:string date:datetime location:string description:text event_type:string 'leg1distance:decimal{6,3}' 'leg2distance:decimal{6,3}' 'leg3distance:decimal{6,3}'`
    - [ ] `rails generate scaffold Participation user:references event:references planned:boolean performed:boolean`
    - [ ] Ensure participations are deleted when user or event is deleted: ```
        inject_into_file "app/models/user.rb", "  has_many :participations, dependent: :destroy\n", after: "ApplicationRecord\n" 
        inject_into_file "app/models/event.rb", "  has_many :participations, dependent: :destroy\n", after: "ApplicationRecord\n"
        ```
    - [ ] Ensure integration tests continue to work: ```
        ['events', 'participations'].all? { |s| 
          gsub_file "test/controllers/#{s}_controller_test.rb", /setup do/, <<~RUBY.indent(2)
            include Devise::Test::IntegrationHelpers
            setup do
              sign_in users(:one)
          RUBY
        }
        ```
    - [ ] `rails db:migrate`
    - [ ] `exec rubocop -a`
    - [ ] `rake test`
    - [ ] `git add . && git commit -m "Add Basic Database Classes for Sisuman" && git push`

  - Add Trestle Admin
    - [ ] `bundle add trestle`
    - [ ] `rails g trestle:install`
    - [ ] `rails g trestle:resource User`
    - [ ] `rails g trestle:resource Event`
    - [ ] `rails g trestle:resource Participation`
    - [ ] ``gsub_file "config/initializers/trestle.rb", '# config.root = "/"', 'config.root = "/"'``
    - [ ] `rails db:migrate`
    - [ ] `exec rubocop -a`
    - [ ] `git add . && git commit -m "Add Trestle Admin" && git push`

  - Trestle Auth
    - [ ] `bundle add trestle-auth`
    - [ ] `rails g trestle:auth:install User --devise`
    - [ ] `rails db:migrate`
    - [ ] `exec rubocop -a`
    - [ ] `git add . && git commit -m "Add Trestle Auth" && git push`

  - Add Roles via Rolify
    - [ ] `bundle add rolify`
    - [ ] `rails g rolify Role User`
    - [ ] Cache roles: `ruby -pi -e 'sub(/rolify/, "rolify after_add: ->(u,_){ u.touch }, after_remove: ->(u,_){ u.touch }\n\n  def has_role?(*args)\n    Rails.cache.fetch([cache_key_with_version, '"'"'has_role?'"'"', *args]) { super }\n  end\n")' app/models/user.rb`
    - [ ] Ensure only Admin can access /admin path: `sed -i '/  # config.before_action do/i\\ \ config.before_action do |controller|\\n    if !current_user || !current_user.has_role?(:admin)\\n      flash[:alert] = "Administrator access required."\\n      redirect_to Trestle.config.root\\n    end\\n  end' config/initializers/trestle.rb`
    - [ ] `rails db:migrate`
    - [ ] `exec rubocop -a`
    - [ ] `git add . && git commit -m "Add Roles via Rolify and allow only admin to access admin interface" && git push`

  - Create Admin User
    - [ ] `rails runner 'User.create!(email: "#{FROM_EMAIL}", password: "#{TTY::Prompt.new.mask("Enter password for #{FROM_EMAIL}:")}")'`
    - [ ] `rails runner 'User.find_by(email: "#{FROM_EMAIL}").add_role(:admin).save!'`

  - Add Annotate Gem for Models
    - [ ] `bundle add annotaterb --group development`
    - [ ] `rails g annotate_rb:install`
    - [ ] Run migration to create annotations: `rails db:migrate`
    - [ ] `exec rubocop -a`
    - [ ] `git add . && git commit -m "Add AnnotateRb Gem" && git push`
    
