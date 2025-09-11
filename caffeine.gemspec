# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = 'caffeine'
  spec.version       = '0.0.1'
  spec.authors       = ['Rob Durst']
  spec.email         = ['rob@brickellresearch.org']

  spec.summary       = ''
  spec.description   = ''
  spec.homepage      = 'https://github.com/Brickell-Research/caffeine'
  spec.license       = 'MIT'

  spec.files         = Dir['lib/**/*', 'README.md', 'LICENSE']
  spec.require_paths = ['lib']

  spec.required_ruby_version = '3.4.5'

  spec.add_dependency 'sorbet-runtime'

  spec.metadata['rubygems_mfa_required'] = 'true'
end
