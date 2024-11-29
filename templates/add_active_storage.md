
  - Enable active storage
    - [ ] `rails active_storage:install`
    - [ ] Ensure Imageprocessing Gem is available: `bundle info image_processing || bundle add image_processing`
    - [ ] Ensure libvips is available (it already is in Dockerfile): `dpkg -l libvips || sudo apt install -y libvips`
    - [ ] `rails db:migrate`
    - [ ] `bundle exec rubocop -a`
    - [ ] `git add . && git commit -m "Add Active Storage" && git push`