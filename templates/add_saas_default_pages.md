    - Option 1 - Add waitlist table to admin interface: `rails g trestle:resource Waitlist`
    - [ ] Option 2 - Add waitlist table to admin interface: ```
      create_file "app/admin/waitlists.rb", <<~RUBY
        Trestle.resource(:waitlists) do
          menu do
            item :waitlists, icon: "fa fa-star"
          end
        
          table do
            column :email
            column :status, format: :tags, align: :center
            column :created_at, align: :center
            column :updated_at, align: :center
        
            actions do |toolbar, instance, admin|
              toolbar.edit if admin && admin.actions.include?(:edit)
              toolbar.delete if admin && admin.actions.include?(:destroy)
              toolbar.link 'Invite', instance, action: :invite, method: :post, style: :primary, icon: "fa fa-check" if instance.pending?
            end
          end
        
          controller do
            def invite
              id = params[:id]
              flash[:message] = "Invitation will be sent"
              InviteAfterWaitListJob.perform_later(waitlist_id: id)
              redirect_back fallback_location: admin.path(:show, id: id)
            end
          end
          
          routes do
            post :invite, on: :member
          end
        end
      RUBY
      ```
    - [ ] `bundle exec rubocop -a && rake test:all && git add . && git commit -m "Implement waitlist feature" && git push`

  - Add Pricing Page
    - [ ] **Create the `PricingTier` model with necessary attributes**:
    ```bash
    rails generate model PricingTier name:string 'monthly_price:decimal{8,2}' 'annual_price:decimal{8,2}' active:boolean
    ```
    - [ ] **Create the `Feature` model**:
      ```bash
      rails generate model Feature name:string description:text
      ```

    - [ ] **Create the `FeatureTier` join model to associate Features with Pricing Tiers**:
      ```bash
      rails generate model FeatureTier pricing_tier:references feature:references quota:integer unlimited:boolean
      ```

    - [ ] **Migrate the database**:
      ```bash
      rails db:migrate
      ```

    - **Set up model associations**
      - [ ] In `app/models/pricing_tier.rb`:
        ```ruby
        inject_into_class "app/models/pricing_tier.rb", "PricingTier", <<~'RUBY'.indent(2)
          has_many :feature_tiers, dependent: :destroy
          has_many :features, through: :feature_tiers
        RUBY
        ```

      - [ ] In `app/models/feature.rb`:
        ```ruby
        inject_into_class "app/models/feature.rb", "Feature", <<~'RUBY'.indent(2)
          has_many :feature_tiers, dependent: :destroy
          has_many :pricing_tiers, through: :feature_tiers
        RUBY
        ```

    - Seed some sample data
      - [ ] Create `db/seeds.rb`:
        ```ruby
        append_file "db/seeds.rb", <<~'RUBY'
          # Clear existing data
          PricingTier.destroy_all
          Feature.destroy_all
          FeatureTier.destroy_all
          
          # Create Features
          features = [
            { name: 'Feature A', description: 'Description of Feature A' },
            { name: 'Feature B', description: 'Description of Feature B' },
            { name: 'Feature C', description: 'Description of Feature C' }
          ].map { |attrs| Feature.create!(attrs) }
          
          # Create Pricing Tiers
          tiers = [
            { name: 'Basic', monthly_price: 0.00, annual_price: 0.0, active: true },
            { name: 'Pro', monthly_price: 9.99, annual_price: 99.99, active: true },
            { name: 'Enterprise', monthly_price: 29.99, annual_price: 299.99, active: true }
          ].map { |attrs| PricingTier.create!(attrs) }
          
          # Associate Features with Pricing Tiers
          tiers.each_with_index do |tier, index|
            features.each_with_index do |feature, index2|
              tier.feature_tiers.create!(
                feature: feature,
                quota: (index * 10) + index2 * 5, # Example quota
                unlimited: index == 2    # Unlimited for Enterprise tier
              )
            end
          end
        RUBY
        ```

    - [ ] Run seeds: `rails db:seed`
    - [ ] Create `PricingController` with `index` action: `rails generate controller Pricing index --skip-routes`

    - [ ] Add route for the pricing page:
      ```ruby
      route 'get "pricing", to: "pricing#index"'
      ```

    - [ ] **Update navigation to include a link to the pricing page**:
      ```ruby
      inject_into_file "app/views/layouts/application.html.erb", after: /<nav>\s*<ul>.*?<ul>\n/m do
        <<~ERB.indent(10)
          <li><%= link_to 'Pricing', pricing_path %></li>
        ERB
      end
      ```

    - [ ] **Implement the `index` action in `PricingController`**:
      ```ruby
      gsub_file "app/controllers/pricing_controller.rb", /  def index\n  end\n/, <<~'RUBY'.indent(2)
        skip_before_action :authenticate_user!

        def index
          @pricing_tiers = PricingTier.where(active: true).includes(feature_tiers: :feature)
        end
      RUBY
      ```

    - [ ] Create the `index.html.erb` view for the pricing page using CSS Grid:
      ```ruby
      create_file "app/views/pricing/index.html.erb", <<~'ERB'
        <% content_for :container_class, "container" %>
        
        <h1>Pricing Plans</h1>
        
        <section class="pricing-grid">
          <% @pricing_tiers.each do |tier| %>
            <div class="pricing-card">
              <h2><%= tier.name %></h2>
              <p class="price">
                <% if tier.monthly_price == 0 %>
                  <strong>Free</strong>
                <% else %>
                  <strong><%= number_to_currency(tier.monthly_price, precision: 0) %></strong> / month 
                <% end %>
              </p>
              <p>
                <%= link_to 'Select Plan', new_user_registration_path(plan: tier.id), role: 'button' %>
              </p>
              <ul>
                <% tier.feature_tiers.each do |feature_tier| %>
                  <% feature = feature_tier.feature %>
                  <li<%= ' class="unavailable"'.html_safe if feature_tier.quota == 0 %>>
                    <% if feature_tier.unlimited -%>
                      Unlimited 
                    <%- elsif feature_tier.quota == 0 -%>
                      No
                    <%- else -%>
                      Up to <%= feature_tier.quota %>
                    <%- end -%>
                    <%= content_tag(:span, feature.name, title: feature.description) %>
                  </li>
                <% end %>
              </ul>
            </div>
          <% end %>
        </section>
      ERB
      ```

    - [ ] **Add custom CSS for the pricing grid to `picocss.css`**:
      ```ruby
      append_file "app/assets/stylesheets/picocss.css", <<~'CSS'

        /* Pricing Grid Styles */
        .pricing-grid {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
          gap: var(--pico-spacing);
        }

        .pricing-card {
          border-radius: var(--pico-border-radius);
          padding: var(--pico-spacing);
          background-color: #f1f1f1;
        }

        .pricing-card .price {
          font-size: 1.5em;
          margin: var(--pico-spacing) 0;
        }

        .pricing-card ul {
          padding-left: 0;
        }

        .pricing-card ul li {
          position: relative;
          list-style: none;
          padding-left: calc(1.25 * var(--pico-spacing)); /* Adjust spacing as needed */
        }

        .pricing-card ul li::before {
          content: '';
          position: absolute;
          left: 0;
          top: 50%;
          transform: translateY(-50%);
          width: 1em;
          height: 1em;
          background-image: var(--pico-icon-valid);
          background-size: contain;
          background-position: center;
        }

        .pricing-card ul .unavailable::before {
          background-image: var(--pico-icon-invalid);
        }
      CSS
      ```

    - [ ] Manually review the pricing page and adjust styling as needed.

    - [ ] **Commit the changes**:
      ```bash
      bundle exec rubocop -a
      git add .
      git commit -m "Add pricing page with CSS Grid layout"
      git push
      ```