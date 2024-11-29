# Add a user profile to the PicoCSS-based application
# Uses table users for the profile
# In retrospect I wonder, If I should have used a separate table as in https://dev.to/skrix/devise-user-profile-1f0h

- [ ] Generate migration to add profile fields to users: `rails generate migration AddProfileFieldsToUsers nickname:string gender:integer date_of_birth:date visible_to_others:boolean`

- [ ] Create a `Profile` model: ```create_file 'app/models/profile.rb', <<~RUBY
      class Profile < ApplicationRecord
        # Submodel of User
        self.table_name = 'users'
        enum :gender, { male: 0, female: 1, other: 2, prefer_not_to_say: 3 }
        
        validates :nickname, presence: true, length: { maximum: 50 }
        validates :gender, presence: true
        validates :date_of_birth, presence: true
        validates_inclusion_of :visible_to_others, in: [true, false]
      end
    RUBY
    ```

- [ ] Ensure users have a valid profile before accessing the site: ```ruby
    inject_into_class 'app/controllers/application_controller.rb', 'ApplicationController', <<~RUBY

      # Ensure that users have a valid profile before they can access the site
      before_action :check_profile

      def check_profile
        return unless current_user.present?
        return if devise_controller?

        profile = Profile.find(current_user.id)
        unless profile.valid?
          flash["notice"] = [*flash["notice"], "Please complete your profile"].uniq
          redirect_to edit_profile_path
        end
      end
    RUBY
    ```

- [ ] Add `gender` enum to `User` model: ```ruby
    inject_into_class 'app/models/user.rb', 'User', "  enum :gender, { male: 0, female: 1, other: 2, prefer_not_to_say: 3 }\n"
    ```

- [ ] Update profile link in the application layout: ```ruby
    gsub_file 'app/views/layouts/application.html.erb', '<a href="#">Profile</a>', '<%= link_to "Profile", profile_path %>'
    ```

- [ ] Add profile routes:
    ```ruby
    inject_into_file 'config/routes.rb', after: "Rails.application.routes.draw do\n" do
      <<~RUBY

        resource :profile, only: [:edit, :update]
        get :profile, to: 'profiles#edit'
        resolve('Profile') { [:profile] }

      RUBY
    end
    ```

- [ ] ```create_file 'app/controllers/profiles_controller.rb', <<~RUBY
        class ProfilesController < ApplicationController
          skip_before_action :check_profile
          before_action :set_profile, only: %i[ show edit update destroy ]

          # GET /profiles/1/edit
          def edit
          end

          # PATCH/PUT /profiles/1 or /profiles/1.json
          def update
            respond_to do |format|
              if @profile.update(profile_params)
                format.html { redirect_to root_path, notice: "Profile was successfully updated." }
                format.json { render :show, status: :ok, location: @profile }
              else
                format.html { render :edit, status: :unprocessable_entity }
                format.json { render json: @profile.errors, status: :unprocessable_entity }
              end
            end
          end

          private
            # Use callbacks to share common setup or constraints between actions.
            def set_profile
              @profile = Profile.find(current_user.id)
            end

            # Only allow a list of trusted parameters through.
            def profile_params
              params.require(:profile).permit(:nickname, :gender, :visible_to_others, :date_of_birth)
            end
        end

    RUBY
    ```

- [ ] ```create_file 'app/views/profiles/_form.html.erb', <<~ERB
    <%= form_with(model: profile) do |form| %>
      <% if profile.errors.any? %>
        <div role="alert">
          <h2><%= pluralize(profile.errors.count, "error") %> prohibited this profile from being saved:</h2>
          <ul>
            <% profile.errors.full_messages.each do |message| %>
              <li><%= message %></li>
            <% end %>
          </ul>
        </div>
      <% end %>

      <fieldset>
        <%= form.label(:nickname) do |builder| %>
          <%= builder.translation %>
          <%= form.text_field :nickname %>
        <% end %>

        <%= form.label(:date_of_birth) do |builder| %>
          <%= builder.translation %>
          <%= form.date_field :date_of_birth %>
        <% end %>

        <fieldset>
          <legend>Gender</legend>
          <%= 
            form.collection_radio_buttons(:gender, User.genders, :first, :first) do |b| 
              b.radio_button + b.label { b.text.humanize }
            end 
          %>
        </fieldset>

        <fieldset>
          <%= form.label(:visible_to_others) do |builder| %>
            <%= builder.translation %>
          <% end %>      
          <%= form.radio_button :visible_to_others, true %> <%= form.label :visible_to_others, "Visible to other users", value: true %>
          <%= form.radio_button :visible_to_others, false %> <%= form.label :visible_to_others, "Hidden from other users", value: false %>
        </fieldset>
      </fieldset>

      <%= form.submit %>
    <% end %>
    ERB
    ```

- [ ] ```create_file 'app/views/profiles/edit.html.erb', <<~ERB
        <% content_for :title, "Editing profile" %>

        <h1>Profile</h1>

        <%= render "form", profile: @profile %>
      ERB
      ```

- [ ] `rails db:migrate`
- [ ] Review manually
- [ ] `bundle exec rubocop -a && rake test && git add . && git commit -m "Add a user profile" && git push`