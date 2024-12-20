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
  - [ ] `rake test:all`
  - [ ] Create Github Repo privately: `gh repo create --private --source=.`
  - [ ] `echo "# #{APP_NAME} Readme" >> README.md`
  - [ ] `rails db:migrate`
  - [ ] `git add .`
  - [ ] `git commit -m "rails new #{APP_NAME}"`
  - [ ] `git push --set-upstream origin main`

- Update credential management to the per-environment way of Rails >= 7
  - [ ] ```gsub_file ".gitignore", /config\/master.key/, "config/**/*.key"```
  - [ ] `mkdir config/credentials`
  - [ ] `mv config/master.key config/credentials/production.key`
  - [ ] `mv config/credentials.yml.enc config/credentials/production.yml.enc`
  - [ ] Review production credentials: `rails credentials:edit --environment production`
  - [ ] `git add *.yml.enc .gitignore`
  - [ ] `git commit -m "Update credential management to Rails >= 6"`

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
  - [ ] Secure all controllers:
    ```ruby
    inject_into_class "app/controllers/application_controller.rb", 'ApplicationController', "  before_action :authenticate_user!\n"
    ```
  - [ ] Except Home controller:
    ```ruby
    inject_into_class "app/controllers/home_controller.rb", 'HomeController', "  skip_before_action :authenticate_user!, only: :index\n"
    ```
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
  - [ ] `bundle exec rubocop -a`
  - [ ] `git add . && git commit -m "Add devise" && git push`

  - Add some useful Rails extensions (from my perspective):
    - [ ] ```create_file "lib/tasks/esbuild_clobber.rake", <<~'RUBY'
          namespace :esbuild do
            desc "Remove esbuild build artifacts"
            task :clobber do
              rm_rf Dir["app/assets/builds/**/[^.]*.{js,js.map,css,css.map,ttf,woff2}"], verbose: false
            end
          end

          if Rake::Task.task_defined?("assets:clobber")
            Rake::Task["assets:clobber"].enhance(["esbuild:clobber"])
          end
        RUBY
      ```
    - [ ] ``` create_file "config/initializers/shorten_etag.rb", <<~'RUBY'
          return if Rails.env.production?

          module Sprockets 
            class Asset

              #
              # Override etag to return more concise names in development 2^64 bit should be enough to prevent a collision (it is enough for esbuild)
              #
              def etag
                version = environment_version

                if version && version != ""
                  DigestUtils.hexdigest(version + digest)[0, 10]
                else
                  DigestUtils.pack_hexdigest(digest)[0, 10]
                end
              end
            end
          end
        RUBY
      ```
    - [ ] ```create_file "config/initializers/css_sourcemapping_url_process.rb", <<~'RUBY'
          # config/initializers/css_sourcemapping_url_process.rb

          # Rewrites source mapping urls with the digested paths and protect against semicolon appending with a dummy comment line
          class CssSourcemappingUrlProcessor
            REGEX = /(\/\*\s*#\s*sourceMappingURL=)(.*\.map)/

            class << self
              def call(input)
                env     = input[:environment]
                context = env.context_class.new(input)
                filename = File.basename(input[:filename])

                data = input[:data]
                data = data.gsub(REGEX) do |match|
                  start, sourcemap = $1, $2
                  sourcemap_logical_path = combine_sourcemap_logical_path(sourcefile: input[:name], sourcemap: sourcemap)

                  begin
                    "#{start}#{sourcemap_asset_path(sourcemap_logical_path, context: context)}"
                  rescue Sprockets::FileNotFound
                    env.logger.warn "Sourcemap file not found: '#{sourcemap_logical_path}' for #{filename}"
                    match # Return the original match - Better than nothing
                  end
                end

                { data: data }
              end

            private
              def combine_sourcemap_logical_path(sourcefile:, sourcemap:)
                if (parts = sourcefile.split("/")).many?
                  parts[0..-2].append(sourcemap).join("/")
                else
                  sourcemap
                end
              end

              def sourcemap_asset_path(sourcemap_logical_path, context:)
                # FIXME: Work-around for bug where if the sourcemap is nested two levels deep, it'll resolve as the source file
                # that's being mapped, rather than the map itself. So context.resolve("a/b/c.js.map") will return "c.js?"
                if context.resolve(sourcemap_logical_path) =~ /\.map/
                  context.asset_path(sourcemap_logical_path)
                else
                  raise Sprockets::FileNotFound, "Failed to resolve source map asset due to nesting depth"
                end
              end
            end
          end

          Sprockets.register_postprocessor "text/css", CssSourcemappingUrlProcessor
        RUBY
        ```
    - [ ] `rake test`
    - [ ] `bundle exec rubocop -a`
    - [ ] `git add . && git commit -m "Add my monkey patches for Rails" && git push`

  - Add that browser is launched with `bin/dev` on a predictable but random port to avoid collisions
    - [ ] Create bin/browser: ```create_file "bin/browser", <<~'BASH'
        #!/bin/bash
        # Script to launch browser when server at the given port is ready
        # Usage: bin/browser [URL=localhost] [PORT=3000]
        # Can be launched with URL as subdomain.localhost, because modern browsers support this.
        # Script will not exit to prevent foreman to terminate also all other processes 

        # Assign URL and port from arguments, defaulting to localhost and 3000 if not provided
        URL=${1:-localhost}
        PORT=${2:-3000}

        # If the URL is a subdomain of localhost, substitute it with "localhost" for /dev/tcp check
        TCP_URL=$URL
        if [[ "$URL" == *.localhost ]]; then
          TCP_URL=localhost
        fi

        echo "Waiting for http://$URL:$PORT to become available..."

        # Wait for the specified port to become allocated and launch the browser
        {
          while ! echo -n > /dev/tcp/$TCP_URL/$PORT; do
            sleep 1
          done
        } 2>/dev/null

        # Detect the appropriate browser command (wslview, open, or xdg-open)
        # Start with wslview to start the host browser in WSL2
        if command -v wslview > /dev/null; then
          OPEN_CMD="wslview"
        elif command -v open > /dev/null; then
          OPEN_CMD="open"
        elif command -v xdg-open > /dev/null; then
          OPEN_CMD="xdg-open"
        else
          echo "No supported command for opening command found. Please install wslview, open, or xdg-open. Press Enter to Close."
          read
        fi

        # Replace with open for MacOS or xdg-open for Linux
        $OPEN_CMD http://$URL:$PORT

        echo "Browser launched. Press Enter to Close."

        # Prevent the script from terminating immediately after launching the browser
        read
        BASH
      ```
    - [ ] Make script executable: `chmod +x bin/browser`
    - [ ] Modify Foreman to (1) launch browser on predictable port and (2) open APP_NAME.localhost: ```
        require 'digest' 
        # Generate a port based on the app name between 3000 and 29900 in 100 increments
        PORT = 3000 + 100 * ::Digest::SHA256.hexdigest(APP_NAME)[0...15].to_i % 270
      
        gsub_file "Procfile.dev", /bin\/rails server/, 
          "\\0 -p #{PORT}\nbrowser: bin/browser #{APP_NAME}.localhost #{PORT}"
     
    ```
    - [ ] `git add . && git commit -m "Add bin/browser to launch browser with bin/dev" && git push`

  - [ ] Start Visual Studio: `code .`
    - [ ] Manually review the generated code

  - Add Picocss
    - [ ] `yarn add @picocss/pico`
    - [ ] Update application.css to accommodate esbuild creating application.css now: `mv app/assets/stylesheets/application.css app/assets/stylesheets/app.css`
    - [ ] Import app.css and pico.css via js: ```append_file "app/javascript/application.js", <<~JS
            // Application.css
            import "../assets/stylesheets/app.css"

            // Use Picocss
            import "@picocss/pico/css/pico.css" // Rather than "@picocss/pico" which includes pico.min.css"
            import "../assets/stylesheets/picocss.css"
          JS
        ```
    - [ ] Create `app/assets/stylesheets/picocss.css` with custom CSS for Rails: ```create_file "app/assets/stylesheets/picocss.css", <<~CSS
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

        /* Prevent loading indicator from appearing on form elements */
        form[aria-busy="true"]::before, turbo-frame[aria-busy="true"]::before {
          display: none;
        }

        form[aria-busy="true"] {
          white-space: normal;
        }
     
        turbo-frame[aria-busy="true"] {
          position: relative;
        }

        /* Apply loading styles only to turbo-frame elements */
        [aria-busy="true"] button {
          &::before {
            content: "";
            position: absolute;
            display: block;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            width: 1em;
            height: 1em;
            background-image: var(--pico-icon-loading); /* Ensure this variable is defined */
            background-size: 1em auto;
            background-repeat: no-repeat;
            z-index: 2; /* Ensure the loading icon is above the overlay */
          }
        }

        /* Remove margin-bottom from last button in a form */
        [type=submit],
        [type=reset],
        [type=button] {
          &:last-child {
            margin-bottom: 0px;
          }

          /* Also remove if next input after button is a hidden input (for button_to helper) */
          &:has(+ [type=hidden]) {
            margin-bottom: 0px;
          }
        }
        
        /* Add spacing between forms */
        form + form {
          margin-top: var(--pico-spacing);
        }

        /* Highlight column */
        .td-primary {
          background-color: var(--pico-blue-50);
        }

        /* Styling for definition lists to match Pico CSS aesthetics */
        article dl {
          display: grid;
          grid-template-columns: max-content 1fr;
          gap: 0.5rem 1rem;
        }

        article dl dl { 
          margin-bottom: 0px;
        }

        /* Style for the labels (dt elements) */
        article dt {
          margin: 0;
          padding: var(--pico-form-element-spacing-vertical) 0;
          font-weight: bold;
          color: var(--pico-color);
        }

        /* Style for the data (dd elements) */
        article dd {
          --pico-background-color: var(--pico-form-element-background-color);
          --pico-border-color: var(--pico-form-element-border-color);
          --pico-color: var(--pico-form-element-color);
          --pico-box-shadow: none;
          margin: 0;
          padding: var(--pico-form-element-spacing-vertical) var(--pico-form-element-spacing-horizontal);
          border: var(--pico-border-width) solid var(--pico-border-color);
          border-radius: var(--pico-border-radius);
          background-color: var(--pico-background-color);
          color: var(--pico-color);
          font-weight: var(--pico-font-weight);
          line-height: var(--pico-line-height);
          transition:
            background-color var(--pico-transition),
            border-color var(--pico-transition),
            color var(--pico-transition),
            box-shadow var(--pico-transition);
        }

        /* Use it to make the main container narrow */
        .container-sm {
          max-width: 510px;
        }

        .container-md {
          max-width: 700px;
        }

        /* Use to ensure header, main content, and footer layed out correctly */
        html body {
          display: grid;
          grid-template-rows: auto 1fr auto;
          align-items: start;
          min-height: 100vh
        }

        .hero {
          display: grid;
          grid-template-columns: 1fr;
          column-gap: var(--pico-homepage-spacing-horizontal);
          row-gap: calc(var(--pico-homepage-spacing-vertical)/2);
          justify-items: center;
          margin-top: calc(var(--pico-homepage-spacing-vertical)/2);
          margin-bottom: 0;
        }
      CSS
      ```
    - Wrap body content in a main container:
      - [ ] Opening tag: ```inject_into_file "app/views/layouts/application.html.erb", <<~ERB.indent(4), after: "<body>\n"
          <main class="<%= content_for(:container_class) || "container" %>">
        ERB
        ```
      - [ ] Closing tag: ```inject_into_file "app/views/layouts/application.html.erb", "    </main>\n", before: "  </body>"```
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
                          <li><%= link_to "Change Password", edit_user_registration_path %></li>
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
    - [ ] Disable wrapping with field_with_errors div: ```
          create_file "config/initializers/field_with_errors.rb", <<~RUBY
            # config/initializers/field_with_errors.rb
            ActionView::Base.field_error_proc = proc do |html_tag, instance|
              # Disable the built-in wrapping of fields with errors div          
              # Could use aria-invalid="true" in the following way, but it isn't very pretty
              # html_tag.gsub(/<input/, "\\0 aria-invalid=\"true\"").html_safe
              html_tag.html_safe
            end
          RUBY
          ```
    - [ ] Update background color in PWA Manifest to white: ```gsub_file "app/views/pwa/manifest.json.erb", /"background_color": "red"/, %Q["background_color": "#FFFFFF"]```
    - [ ] `bundle exec rubocop -a`
    - [ ] `git add . && git commit -m "Add Picocss" && git push`

  - Generate Favicon for App:
    - [ ] `dpkg -l inkscape || sudo apt install -y inkscape`
    - [ ] `dpkg -l fonts-roboto || sudo apt install -y fonts-roboto`
    - [ ] `gem install victor`
    - [ ] `gem install letter_avatar`
    - [ ] Generate Favicon SVG using colors from Letter Avatar using Roboto Font: ```
        require 'victor'
        require 'letter_avatar/colors'
        color = LetterAvatar::Colors.with_iwanthue("#{APP_NAME}").pack("C*").unpack("H*").first       
        svg = Victor::SVG.new viewBox: '0 0 128 128' do
          rect x: 0, y: 0, width: 128, height: 128, fill: "\##{color}"
          text "#{APP_NAME.upcase[0]}", x: '50%', y: '56%', 'text-anchor': 'middle', 'dominant-baseline': 'middle', 'font-family': 'Roboto Medium', 'font-size': 100, fill: '#FFFFFF', 'fill-opacity': "0.85", 'font-weight': '500'
          # Original LetterAvatar is font-size: 85, opacity: 0.65
        end
        svg.save "public/icon.svg"
        # Replace Theme Color in PWA manifest
        gsub_file "app/views/pwa/manifest.json.erb", /"theme_color": "red"/, %Q["theme_color": "##{color}"]
      ```
    - [ ] Convert to stroke so the font isn't needed: `inkscape --actions="select-all;object-stroke-to-path;export-filename:public/icon.svg;export-do" "public/icon.svg"`
    - Generate favicon ICO
      - [ ] `dpkg -l icoutils || sudo apt-get install -y icoutils`
      - [ ] Use bash script to generate favicon.ico: ```create_file "bin/favicon", <<~'BASH'
            #!/bin/bash

            # Script to generate favicon.ico from icon.svg
            # Usage: bin/favicon [ICON=icon.svg] [FAVICON=favicon.ico]
            # Default values are icon.svg and favicon.ico

            ICON=${1:-icon.svg}
            FAVICON=${2:-favicon.ico}

            cd public

            # Exit if $ICON does not exist
            if [ ! -f $ICON ]; then
              echo "File $ICON does not exist"
              exit 1
            fi

            for size in 16 24 32 48 64 96 128 256; do
              inkscape --export-filename $size.png -w $size -h $size $ICON >/dev/null 2>/dev/null
            done

            for size in 16 24 32 48; do
              convert -colors 256 +dither $size.png png8:$size-8.png
              convert -colors 16  +dither $size-8.png $size-4.png
            done

            icotool -c -o $FAVICON 16.png 24.png 32.png 48.png 16-8.png 24-8.png 32-8.png 48-8.png 16-4.png 24-4.png 32-4.png 48-4.png 64.png 96.png -r 128.png -r 256.png

            rm 16.png 24.png 32.png 48.png 16-8.png 24-8.png 32-8.png 48-8.png 16-4.png 24-4.png 32-4.png 48-4.png 64.png 96.png 128.png 256.png
          BASH
        ```
      - [ ] Make script executable: `chmod +x bin/favicon`
      - [ ] `bin/favicon`
    - [ ] Export as PNG: `inkscape --export-width=600 --export-type=png --export-filename="public/icon.png" "public/icon.svg"`
    - The following would be a png only alternative: 
      - `gem install letter_avatar`
      - `sudo apt-get install -y imagemagick`
      - ```
      require 'letter_avatar'
      LetterAvatar.setup do |config|
        config.colors_palette = :iwanthue
        config.cache_base_path   = 'tmp/'
        config.pointsize = 400
      end
      path = LetterAvatar.generate "#{APP_NAME}", 600
      FileUtils.mv path, "public/favicon-letter.png"
      ```
    - [ ] Link from application.html.erb: ``gsub_file "app/views/layouts/application.html.erb", /<nav>\n(\s*)<ul>/,  "\\0\n\\1  <li><img src=\"/icon.svg\" alt=\"#{APP_NAME} Logo\" width=\"64\"></li>" ``
    - [ ] `bundle exec rubocop -a && rake test && git add . && git commit -m "Generate Letter Logo" && git push`

  - Adapt Devise for Picocss:
    - [ ] `rails generate devise:views`
    - [ ] Disable password confirmation: ``Dir.glob("app/views/devise/registrations/*.html.erb").each { |f| gsub_file f, /  <div class="field">(?:(?!div).)*?:password_confirmation.*?<\/div>\n\n/m, '' } ``
    - [ ] Unset minimum password length hint for obvious values: ```
        Dir.glob("app/views/devise/**/*.html.erb").map { |f| 
          gsub_file f, /(?<=if )@minimum_password_length/, "(\\0 || 0) > 8" 
        }.any?
        ```
    - [ ] Remove all <br/> tags: ``Dir.glob("app/views/devise/**/{new,edit}.html.erb").each { |f| gsub_file f, /<br \/>/, "" }``
    - [ ] Wrap all devise forms in <article>: ```
          Dir.glob("app/views/devise/**/*.html.erb").each { |f| 
            gsub_file f, /\n<%= form_for/,                "\n<article>\\0"
            gsub_file f, /\n<%= form_for.*?\n<% end %>/m, "\\0\n</article>"
          }
        ```
    - [ ] Wrap all devise edit forms in <fieldset>: ```
          Dir.glob("app/views/devise/**/{new,edit}.html.erb").each { |f| 
            insert_into_file f, "\n  <fieldset>", before: "\n  <div class=\"field\">", once: true
            insert_into_file f, "\n  </fieldset>", before: "\n\n  <div class=\"actions\">"
          }
        ```
    - [ ] Wrap devise view in container-sm: ```inject_into_file "app/views/layouts/application.html.erb", <<~ERB.indent(4), before: "    <main" 
          <% content_for(:container_class, "container container-sm") if devise_controller? %>
        ERB
        ```
    - [ ] Improve the edit_user_registration form: ```
          # Replace Unhappy?+div with article tag 
          gsub_file "app/views/devise/registrations/edit.html.erb", /<div>Unhappy\? (.*?)<\/div>/m, "<article>\\1</article>"
          # Put <small> note below the password fields
          gsub_file "app/views/devise/registrations/edit.html.erb", / <i>(.*?)<\/i>(\s*)(<%= .*? %>)/m, "\\2\\3\\2<small>\\1</small>"
        ```
    - [ ] `bundle exec rubocop -a && rake test && git add . && git commit -m "Adapt Devise for Picocss" && git push`

  - Adapt View Generation to Picocss:
    - [ ] Update view partial template: ```create_file "lib/templates/erb/scaffold/partial.html.erb.tt", <<~ERB
        <article id="<%%= dom_id <%= singular_name %> %>">
          <dl>
        <% attributes.reject(&:password_digest?).each do |attribute| -%>
            <dt><%= attribute.human_name %>:</dt>
        <% if attribute.attachment? -%>
            <dd><%%= link_to <%= singular_name %>.<%= attribute.column_name %>.filename, <%= singular_name %>.<%= attribute.column_name %> if <%= singular_name %>.<%= attribute.column_name %>.attached? %></dd>
        <% elsif attribute.attachments? -%>
            <dd><%% <%= singular_name %>.<%= attribute.column_name %>.each do |<%= attribute.singular_name %>| %>
              <div><%%= link_to <%= attribute.singular_name %>.filename, <%= attribute.singular_name %> %></div>
            <%% end %></dd>
        <% else -%>
            <dd><%%= <%= singular_name %>.<%= attribute.column_name %> %></dd>
        <% end -%>
        <% end -%>
          </dl>
        </article>
        ERB
        ```
    - [ ] `bundle exec rubocop -a && rake test && git add . && git commit -m "Adapt View Generation for Picocss" && git push`

  - [ ] Add Basic Database Classes for your app below
    - Either use `generate model` or `generate scaffold`
    - For syntax help: https://rails-generate.com/
    - Field names should not include: `type`, `id`, (`hash` or other existing ruby object method names), `created_at|on`, `updated_at|on`, `deleted_at`, `lock_version`, `position`, `parent_id`, `lft`, `rgt`, `quote_value`, `request`, `record`...
      - Check: https://stackoverflow.com/questions/13750009/reserved-names-with-activerecord-models
    - Use the following types for the fields:
      - string
      - text
      - integer
      - float
      - decimal{6,2} - Prefer over float for currency/accurate numbers
      - datetime
      - boolean
      - references
    - Example One:
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
    - Example Two:
      - [ ] `rails generate migration AddAttributesToUsers last_name:string first_name:string`
      - [ ] `rails generate scaffold Requisition name:string first_execution:datetime rrule:string description:text requester:references reporter:references`
      - [ ] Adjust foreign key: ``gsub_file Dir.glob("db/migrate/*_create_requisitions.rb").first, /foreign_key: true/, "foreign_key: { to_table: :users }"``
      - [ ] `rails generate scaffold Report requisition:references status:integer`
      - [ ] Adjust ActiveRecord Relations: ```
          inject_into_file "app/models/user.rb", "  has_many :requisitions, dependent: :destroy\n", after: "ApplicationRecord\n"
          inject_into_file "app/models/user.rb", "  has_many :reports, dependent: :destroy\n", after: "ApplicationRecord\n" 
          inject_into_file "app/models/requisition.rb", "  has_many :reports, dependent: :destroy\n", after: "ApplicationRecord\n"
          inject_into_file "app/models/requisition.rb", ", class_name: 'User'", after: "belongs_to :requester"
          inject_into_file "app/models/requisition.rb", ", class_name: 'User'", after: "belongs_to :reporter"
          inject_into_file "app/models/report.rb", "  enum :status, { open: 0, submitted: 1, archived: 2 }\n", after: "ApplicationRecord\n"
          ```
      - [ ] Ensure integration tests continue to work: ```
          ['requisitions', 'reports'].all? { |s|
            Dir.glob("test/{controllers,system}/#{s}*_test.rb").all? { |f|
              gsub_file f, /  setup do\n/, <<~RUBY.indent(2)
                include Devise::Test::IntegrationHelpers
                setup do
                  sign_in users(:one)
              RUBY
            }
          }
          ```
    - [ ] `rails db:migrate`
    - [ ] `bundle exec rubocop -a`
    - [ ] `rake test:all`
    - [ ] `git add . && git commit -m "Add Basic Database Classes for #{APP_NAME}" && git push`

  - Add Trestle Admin
    - [ ] `bundle add trestle`
    - [ ] `rails g trestle:install`
    - [ ] Add Trestle Admin for each model: ```rails_run <<~RUBY
          Rails.application.eager_load!
          ApplicationRecord.subclasses.map(&:name).all? { |model| 
            puts `rails g trestle:resource \#{model}`
            next $?.success?
          }
        RUBY
      ```
    - [ ] ``gsub_file "config/initializers/trestle.rb", '# config.root = "/"', 'config.root = "/"'``
    - [ ] `rails db:migrate`
    - [ ] `bundle exec rubocop -a`
    - [ ] `git add . && git commit -m "Add Trestle Admin" && git push`

  - Trestle Auth
    - [ ] `bundle add trestle-auth`
    - [ ] `rails g trestle:auth:install User --devise`
    - [ ] `rails db:migrate`
    - [ ] `bundle exec rubocop -a`
    - [ ] `git add . && git commit -m "Add Trestle Auth" && git push`

  - Add Roles via Rolify
    - [ ] `bundle add rolify`
    - [ ] `rails g rolify Role User`
    - [ ] Cache roles: `ruby -pi -e 'sub(/rolify/, "rolify after_add: ->(u,_){ u.touch }, after_remove: ->(u,_){ u.touch }\n\n  def has_role?(*args)\n    Rails.cache.fetch([cache_key_with_version, '"'"'has_role?'"'"', *args]) { super }\n  end\n")' app/models/user.rb`
    - [ ] Ensure only Admin can access /admin path: `sed -i '/  # config.before_action do/i\\ \ config.before_action do |controller|\\n    if !current_user || !current_user.has_role?(:admin)\\n      flash[:alert] = "Administrator access required."\\n      redirect_to Trestle.config.root\\n    end\\n  end' config/initializers/trestle.rb`
    - [ ] `rails db:migrate`
    - [ ] `bundle exec rubocop -a`
    - [ ] `git add . && git commit -m "Add Roles via Rolify and allow only admin to access admin interface" && git push`

  - Create Admin User
    - [ ] `rails runner 'User.create!(email: "#{FROM_EMAIL}", password: "#{TTY::Prompt.new.mask("Enter password for #{FROM_EMAIL}:")}")'`
    - [ ] `rails runner 'User.find_by(email: "#{FROM_EMAIL}").add_role(:admin).save!'`

  - Add `annotaterb` gem (it's a modern version of the 'annotate' gem)
    - [ ] `bundle add annotaterb --group development`
    - [ ] `rails g annotate_rb:install`
    - [ ] Run migration to create annotations: `rails db:migrate`
    - [ ] `bundle exec rubocop -a`
    - [ ] `git add . && git commit -m "Add AnnotateRb Gem" && git push`

  - Install Better Errors with VSCode Integration
    - [ ] `bundle add better_errors binding_of_caller --group development`
    - [ ] Set Editor (WSL): ```create_file "config/initializers/better_errors.rb", <<~RUBY
          if defined?(BetterErrors) && (distro_name = ENV['WSL_DISTRO_NAME'])
            BetterErrors.editor = "vscode://vscode-remote/wsl+\#{distro_name}%{file_unencoded}:%{line}"
          end
        RUBY
        ```
    - [ ] `bundle exec rubocop -a`
    - [ ] `git add . && git commit -m "Add Better Errors" && git push`

  - Add Font Awesome
    - [ ] `yarn add @fortawesome/fontawesome-free`
    - [ ] `echo '\n\n// Use Font Awesome\nimport "@fortawesome/fontawesome-free/css/all"' >> app/javascript/application.js`
    - [ ] Add ttf/woff2 to esbuild: ``inject_into_file "package.json", '--loader:.ttf=file --loader:.woff2=file ', after: 'esbuild app/javascript/*.* '``
    - [ ] Ensure file are marked as digested: ``inject_into_file "package.json", '--asset-names=[name]-[hash].digested ', after: 'esbuild app/javascript/*.* '``
      - See: https://github.com/evanw/esbuild/issues/2092
    - [ ] Remove --public-path: ``gsub_file "package.json", / --public-path=\/assets/, ""``
    - [ ] `bundle exec rubocop -a`
    - [ ] `git add . && git commit -m "Add Font Awesome" && git push`

  - Add Rails Settings Cached and install a wait list
    - [ ] `bundle add rails-settings-cached`
    - [ ] `rails g settings:install`
    - [ ] Insert Wait-List Limit: ```insert_into_file "app/models/setting.rb", <<~RUBY.indent(2), after: "Define your fields\n"
          # Wait-List limit indicates the maximum number of users who can join the app
          # 0 == nobody can sign-up, -1 == unlimited sign-ups
          field :wait_list_limit, type: :integer, default: 0
        RUBY
        ```
    - [ ] Create `Waitlist` model: `rails generate model Waitlist email:string status:integer`
    - [ ] Migrate the database: `rails db:migrate`
    - [ ] Add validations and enum to `Waitlist` model:
      ```ruby
      inject_into_class "app/models/waitlist.rb", "Waitlist", <<~'RUBY'
        validates :email, presence: true
        enum :status, { pending: 0, invited: 1 }, default: :pending
      RUBY
      ```
    - [ ] Add `is_waitlist_active?` method to `Setting` model:
      ```ruby
      inject_into_class "app/models/setting.rb", "Setting", <<~'RUBY'
        def self.is_waitlist_active?
          wait_list_limit == 0 || (wait_list_limit > 0 && User.count >= wait_list_limit)
        end
      RUBY
      ```
    - [ ] Create custom Devise `RegistrationsController` to handle waitlist logic:
      ```ruby
      create_file "app/controllers/users/registrations_controller.rb", <<~'RUBY'
        class Users::RegistrationsController < Devise::RegistrationsController
          def new
            if Setting.is_waitlist_active?
              redirect_to waitlist_path, alert: "Registrations are currently closed."
            else
              super
            end
          end

          def create
            if Setting.is_waitlist_active?
              redirect_to waitlist_path, alert: "Registrations are currently closed."
            else
              super
            end
          end
        end
      RUBY
      ```
    - [ ] Add to routes: ```gsub_file "config/routes.rb", /devise_for :users\n/, 'devise_for :users, controllers: { registrations: "users/registrations" }'```
    - [ ] Create `WaitlistController` with `new` and `create` actions:
      ```ruby
      create_file "app/controllers/waitlist_controller.rb", <<~'RUBY'
        class WaitlistController < ApplicationController
          skip_before_action :authenticate_user!

          def new
            @waitlist_entry = Waitlist.new
          end

          def create
            @waitlist_entry = Waitlist.new(waitlist_params)
            if @waitlist_entry.save
              redirect_to root_path, notice: "You have been added to the waitlist."
            else
              render :new
            end
          end

          private

          def waitlist_params
            params.require(:waitlist).permit(:email)
          end
        end
      RUBY
      ```
    - [ ] Add routes for `WaitlistController` using "waitlist" as a single word:
      ```ruby
      route 'get "waitlist", to: "waitlist#new"'
      route 'post "waitlist", to: "waitlist#create"'
      ```
    - [ ] Create view for `Waitlist#new` action:
      ```ruby
      create_file "app/views/waitlist/new.html.erb", <<~'ERB'
        <% content_for :container_class, "container container-sm" %>
        <h1>Join the Waitlist</h1>
        <%= form_with model: @waitlist_entry, url: waitlist_path do |f| %>
          <%= f.label :email %>
          <%= f.email_field :email %>
          <%= f.submit "Join" %>
        <% end %>
      ERB
      ```
    - [ ] Update navigation to only switch the "Sign up" link to "Join Waitlist" when registrations are closed:
      ```ruby
      gsub_file "app/views/layouts/application.html.erb", /^(\s*)<li>(<%= link_to "Sign up", new_user_registration_path %>)<\/li>\n/, <<~RUBY
        \\1<li>
        \\1  <% if Setting.is_waitlist_active? %>
        \\1    <%= link_to "Join Waitlist", waitlist_path %>
        \\1  <% else %>
        \\1    \\2
        \\1  <% end %>
        \\1</li>
        RUBY
      ```
    - Enter Tag line for Homepage
::var[TAG_LINE]
    - [ ] Replace HomeController view: ```create_file "app/views/home/index.html.erb", <<~ERB, force: true
          <% content_for :container_class, "container container-md hero" %>
          <h1>#{APP_NAME.capitalize}</h1>
          <p>#{TAG_LINE}</p>
          <%= link_to "Join Waitlist", waitlist_path, role: "button" if Setting.is_waitlist_active? %>
        ERB
      ```

  - Customize Home Page
    - [ ] Edit `app/views/home/index.html.erb` to show a welcome message and a link to the events page

  - Prepare app for deployment with Dokku + Postgres:
    - [ ] `bundle add pg --group production`
    - [ ] Disable sqlite for production: ``gsub_file "Gemfile", /gem "sqlite3".*$/, '\0, group: [:development, :test]'``
    - [ ] Swap sqlite for pg in Dockerfile: ``gsub_file "Dockerfile", /sqlite3/, 'postgresql-client'``
    - [ ] Add libpq-dev: ``gsub_file "Dockerfile", /build-essential git/, '\0 libpq-dev'``
    - [ ] Update database.yml: ```gsub_file "config/database.yml", /# SQLite3 write its.*persistent\/storage\/production.sqlite3/m, <<~JSON
          production:
            adapter: postgresql
            encoding: unicode
            pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
            url: <%= ENV['DATABASE_URL'] %>
        JSON
        ```
    - [ ] Make Docker build less noisy: ``gsub_file "Dockerfile", /apt-get install/,  'apt-get -qq install'``
    - [ ] Make Docker build less noisy: ``gsub_file "Dockerfile", /apt-get update -qq/,  'apt-get -qq update'``
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
    - [ ] `git add . && git commit -m "Prepare for production" && git push`

  - Deploy with Dokku
    - Dokku is a self-hosted platform as a service (PaaS) that allows you to deploy your applications with a simple `git push` to your server.
    - Since Rails 7 comes with a `Dockerfile`, Dokku is using Docker for your app and NOT Heroku's buildpacks.
    - To use Dokku you need a server (assuming Ubuntu below) you can SSH into and install Dokku on.
    - By default this won't be the same as #{HOST_NAME}
::var[DEPLOY_HOST]{vps.oezbek.app}
    - [ ] Add [default user name for DEPLOY_HOST](https://stackoverflow.com/q/10197559/278842): ```
        if !user_for_host("#{DEPLOY_HOST}")
          puts "What user name should be used to ssh to #{DEPLOY_HOST}?"
          puts "Enter it here or manually add it to ~/.ssh/config."
          user_name = STDIN.gets.chomp
          File.open("#{Dir.home}/.ssh/config", "a") do |f|
            f.puts
            f.puts "Host #{DEPLOY_HOST}"
            f.puts "  User #{user_name}"
          end
        end
        ```

  - Ensure SSH key exists and is copied to the server:
    - If you don't have an SSH Key: ssh-keygen -t rsa -b 4096 -C '#{FROM_EMAIL}' -N '' -f ~/.ssh/id_rsa
    - [ ] Check for SSH key: `test -f ~/.ssh/id_rsa.pub`
    - [ ] Add local user's SSH pub key to server: `ssh-copy-id #{DEPLOY_HOST}`
      - Alternatively: ssh -o 'ConnectionAttempts 3' 

::var[WRAP_COMMAND]{ssh #{DEPLOY_HOST} -t "#{COMMAND.gsub('"', '\"')}"}

  - [ ] Setup new server - Skip this section if you already have a server with Dokku installed or continue ('y') if you want to perform the setup.
    - Standard Ubuntu Setup before Dokku:
      - [ ] `sudo apt-get install unattended-upgrades`

    - Install Dokku on the server:
      - [ ] `sudo apt-get update`
      - [ ] Install debconf-utils to be able to debconf-get-selections: `sudo apt-get install -y debconf-utils`
      - Preconfigure Dokku installation:
        - [ ] `echo "dokku dokku/vhost_enable boolean true" | sudo debconf-set-selections`
        - [ ] `echo "dokku dokku/hostname string #{HOST_NAME}" | sudo debconf-set-selections`
        - [ ] `echo "dokku dokku/skip_key_file boolean true" | sudo debconf-set-selections`
        - [ ] Output configuration for apt: `sudo debconf-get-selections | grep dokku`
      - [ ] Install latest Dokku (-N to override previous bootstrap.sh download): `wget -N https://dokku.com/bootstrap.sh ; sudo bash bootstrap.sh`
      - [ ] Reboot remote: `nohup bash -c "sleep(1); reboot" &`
      - [ ] Wait for reboot to complete/shell via ruby: `` sleep(20) ``
      - [ ] Install Let's Encrypt plugin: `sudo dokku plugin:install https://github.com/dokku/dokku-letsencrypt.git`
        - [ ] Install cron for auto-renew: `dokku letsencrypt:cron-job --add`
      - [ ] Use same pub key for pushing as for login: `cat ~/.ssh/authorized_keys | dokku ssh-keys:add admin`
        - Alternatively you could ask the user for which SSH key to use for deployment: ```
          loop true
            puts "Enter the path of the SSH pub key which you want to add for dokku `dokku ssh-keys:add`?"
            puts "Press Enter to use the default key: ~/.ssh/id_rsa.pub"
            key_name = STDIN.gets.chomp
            key_name = "~/.ssh/id_rsa.pub" if key_name.empty?
            break if `test -f #{keyname.shellescape}`
            puts "Key file not found. Please try again."
          end
          ssh root@#{DEPLOY_HOST} 
          ```
      - [ ] Add a fallback nginx config:
          ```bash
            echo 'server {
              listen 80 default_server;
              listen [::]:80 default_server;
              listen 443 ssl default_server;
              listen [::]:443 ssl default_server;
              ssl_reject_handshake on;
              return 444;
            }' > /etc/nginx/conf.d/default.conf
            systemctl restart nginx
          ```
      - [ ] Install Postgres: `sudo dokku plugin:install https://github.com/dokku/dokku-postgres.git postgres`

  - Create the app on dokku:
    - [ ] `dokku apps:create #{APP_NAME}`
    - [ ] Update your DNS config so that #{HOST_NAME} A record (or CNAME) points to #{DEPLOY_HOST}
    - [ ] Set domain: `dokku domains:add #{APP_NAME} #{HOST_NAME}`
    - [ ] Set Let's Encrypt email: `dokku letsencrypt:set #{APP_NAME} email #{FROM_EMAIL}`
    - Enable persistent storage: 
      - [ ] Rails uses 1000:1000 which matches heroku: `dokku storage:ensure-directory --chown heroku #{APP_NAME}`
      - [ ] `dokku storage:mount #{APP_NAME} /var/lib/dokku/data/storage/#{APP_NAME}/rails/storage:/rails/storage`
    - [ ] Set Rails to handle assets: `dokku config:set #{APP_NAME} RAILS_SERVE_STATIC_FILES=true`
    - [ ] Create Postgres service: `dokku postgres:create #{APP_NAME}-db`
    - [ ] Link Postgres service: `dokku postgres:link #{APP_NAME}-db #{APP_NAME}`
::var[WRAP_COMMAND]{}

  - On the client side, add Dokku remote and deploy:
    - [ ] Set RAILS_MASTER_KEY: `ssh #{DEPLOY_HOST} "dokku config:set #{APP_NAME} RAILS_MASTER_KEY=$(cat config/credentials/production.key)"`
    - [ ] Add Dokku remote: `git remote add dokku dokku@#{DEPLOY_HOST}:#{APP_NAME}`
    - [ ] Push code to Dokku (this includes migration via bin/docker-entrypoint): `git push dokku main`
::var[WRAP_COMMAND]{ssh #{DEPLOY_HOST} -t "#{COMMAND.gsub('"', '\"')}"}
    - [ ] Enable Let's Encrypt: `dokku letsencrypt:enable #{APP_NAME}`
    - [ ] Rails EXPOSES port 3000 in Dockerfile, so we need port mapping: `dokku ports:add #{APP_NAME} https:443:3000`
::var[WRAP_COMMAND]{}
    - [ ] Open Browser: `bin/browser #{HOST_NAME} 443`
    - [ ] Ensure the application is running at `https://#{HOST_NAME}`

    - Update Dokku Instructions:
      - dokku ps:stop --all
      - dokku-update

  - [ ] Make modern browser also work on Opera on Android
        https://blog.saeloun.com/2024/03/18/rails-7-2-adds-allow-browser-to-set-minimum-versions/
        https://github.com/rails/rails/pull/50505

  - [ ] https://acuments.com/rails-serve-static-files-with-nginx.html

  - [ ] jsbundling does not clean up old files during clobber
