$LOAD_PATH.push File.expand_path('lib', __dir__)
require_relative "lib/mailbounce/version"

Gem::Specification.new do |spec|
  spec.name = "mailbounce"
  spec.version = MailBounce::VERSION
  spec.platform = Gem::Platform::RUBY
  spec.required_ruby_version = ">= 3.4"
  spec.authors = [ "Simon Lev" ]

  spec.summary = "Email delivery failures for Ruby."
  spec.description = "Classify a rejected message and read delivery status notifications, so you know whose fault a bounce was."

  spec.homepage = "https://github.com/mailpiece/mailbounce"
  spec.license = "MIT"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir[
    "lib/**/*.rb",
    "CHANGELOG.md",
    "README.md",
    "LICENSE",
    "mailbounce.gemspec"
  ]
  spec.require_paths = [ "lib" ]

  spec.add_dependency "mail", ">= 2.7"
end
