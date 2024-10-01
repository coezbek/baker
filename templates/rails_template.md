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
  - [ ] `gh repo create --public --source=.`
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
  - [ ] `exec rubocop -a`
  - [ ] `git add . && git commit -m "Add devise" && git push`

  - [ ] Start Visual Studio: `code .`
    - [ ] Manually review the generated code

  - Add Picocss
    - [ ] `yarn add @picocss/pico`
    - [ ] `echo '\n//Use Picocss\nimport "@picocss/pico"' >> app/javascript/application.js`
    - Update application.css to accommodate esbuild creating application.css now:
      - [ ] Move application.css out of the way to prevent conflict with esbuild: `mv app/assets/stylesheets/application.css app/assets/stylesheets/application2.css`
      - [ ] Link application2.css from application.html.erb: `inject_into_file "app/views/layouts/application.html.erb", after: '<%= stylesheet_link_tag "application", "data-turbo-track": "reload" %>\n', '<%= stylesheet_link_tag "application2", "data-turbo-track": "reload" %>'`
    - [ ] Wrap body content in a main container:
      - [ ] `ruby -pi -e 'gsub(/<body>/, %q[<body><main class="container">])' app/views/layouts/application.html.erb`
      - [ ] `ruby -pi -e 'gsub(/<\\/body>/, %q[<\/main><\/body>])' app/views/layouts/application.html.erb`
    - [ ] Append Custom Picocss CSS import to `application.js`: `append_to_file "app/javascript/application.js", 'import "../assets/stylesheets/picocss.css"`
    - [ ] Create `app/assets/stylesheets/picocss.css` with custom CSS for alerts: ```create_file "app/assets/stylesheets/picocss.css", <<~CSS
        /**
        * Custom PicoCSS styles here. Included via app/javascript/application.js
        */ 
        :root {
          --pico-amber-50: #fff8e1;
          --pico-amber-900: #ff6f00;
          --pico-green-50: #e8f5e9;
          --pico-green-800: #1b5e20;
          --pico-red-50: #ffebee;
          --pico-red-900: #b71c1c;
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

        /* Danger alert styles */
        .alert-danger {
          --pico-background-color: var(--pico-red-50);
          --pico-icon: var(--pico-icon-invalid);
          --pico-color: var(--pico-red-900);
        }

        /* Warning alert styles */
        .alert-warning {
          --pico-background-color: var(--pico-amber-50);
          --pico-icon: var(--pico-icon-invalid); /* url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='24' height='24' viewBox='0 0 24 24' fill='none' stroke='%23cc5d00' stroke-width='2' stroke-linecap='round' stroke-linejoin='round'%3E%3Ccircle cx='12' cy='12' r='10'%3E%3C/circle%3E%3Cline x1='12' y1='8' x2='12' y2='12'%3E%3C/line%3E%3Cline x1='12' y1='16' x2='12.01' y2='16'%3E%3C/line%3E%3C/svg%3E"); */
          --pico-color: #cc5d00; /* darkened amber-900 */
        }

        /* Success alert styles */
        .alert-success {
          --pico-background-color: var(--pico-green-50);
          --pico-icon: var(--pico-icon-valid);
          --pico-color: var(--pico-green-800);
        }

        @import "@picocss/pico";
        CSS  
      ```
    - [ ] Replace flash messages in `application.html.erb`:```
      gsub_file "app/views/layouts/application.html.erb", %r{<p class="notice"><%= notice %></p>\s*<p class="alert"><%= alert %></p>}, <<~ERB
        <%= content_tag :div, notice, class: "alert alert-warning" if notice.present? %>
        <%= content_tag :div, alert, class: "alert alert-danger" if alert.present? %>
      ERB
      ```
    - [ ] Insert navigation header after `<body>`:```
          inject_into_file "app/views/layouts/application.html.erb", after: "<body>\n" do
            <<~HTML
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
          inject_into_file "app/views/layouts/application.html.erb", before: "</body>" do
            <<~HTML
              <footer class="container">
                <p><%= year_of_launch = #{Time.now.year}; year_of_launch == Time.now.year ? "" : "\#{year_of_launch} -"%><%= Time.now.year %> #{APP_NAME.capitalize}©</p>
              </footer>
            HTML
          end
          ```
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
    - [ ] `rails db:migrate`
    - [ ] `git add . && git commit -m "Add Basic Database Classes for Sisuman" && git push`

  - Add Trestle Admin
    - [ ] `bundle add trestle`
    - [ ] `rails g trestle:install`
    - [ ] `rails g trestle:resource User`
    - [ ] `rails g trestle:resource Competition`
    - [ ] `rails g trestle:resource Participation`
    - [ ] `rails db:migrate`
    - [ ] `git add . && git commit -m "Add Trestle Admin" && git push`

  - Trestle Auth
    - [ ] `bundle add trestle-auth`
    - [ ] `rails g trestle:auth:install User --devise`
    - [ ] `rails db:migrate`
    - [ ] `git add . && git commit -m "Add Trestle Auth" && git push`

  - Add Roles via Rolify
    - [ ] `bundle add rolify`
    - [ ] `rails g rolify Role User`
    - [ ] Cache roles: `ruby -pi -e 'sub(/rolify/, "rolify after_add: ->(u,_){ u.touch }, after_remove: ->(u,_){ u.touch }\n\n  def has_role?(*args)\n    Rails.cache.fetch([cache_key_with_version, '"'"'has_role?'"'"', *args]) { super }\n  end\n")' app/models/user.rb`
    - [ ] Ensure only Admin can access /admin path: `sed -i '/  # config.before_action do/i\\ \ config.before_action do |controller|\\n    unless !current_user || current_user.has_role?(:admin)\\n      flash[:alert] = "Administrator access required."\\n      redirect_to Trestle.config.root\\n    end\\n  end' config/initializers/trestle.rb`
    - [ ] `rails db:migrate`
    - [ ] `git add . && git commit -m "Add Roles via Rolify and allow only admin to access admin interface" && git push`

  - Create Admin User
    - [ ] `rails runner 'User.create!(email: "#{FROM_EMAIL}", password: "#{TTY::Prompt.new.mask("Enter password for #{FROM_EMAIL}:")}")'`
    - [ ] `rails runner 'User.find_by(email: "#{FROM_EMAIL}").add_role(:admin).save!'`

  - Add Annotate Gem for Models
    - [ ] `bundle add annotaterb --group development`
    - [ ] `rails g annotate_rb:install`
    - [ ] Run migration to create annotations: `rails db:migrate`
    - [ ] `git add . && git commit -m "Add AnnotateRb Gem" && git push`
    
