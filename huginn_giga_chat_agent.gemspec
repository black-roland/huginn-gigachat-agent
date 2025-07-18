# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "huginn_giga_chat_agent"
  spec.version       = '0.1'
  spec.authors       = ["Black Roland"]
  spec.email         = ["mail@roland.black"]

  spec.summary       = %q{Huginn agent for Sber's GigaChat AI}
  spec.description   = %q{Huginn agent that connects to GigaChat API, enabling AI-powered text generation and processing within your Huginn workflows}

  spec.homepage      = "https://github.com/black-roland/huginn-gigachat-agent"
  spec.license       = "MPL-2.0"

  spec.files         = Dir['LICENSE', 'lib/**/*']
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = Dir['spec/**/*.rb'].reject { |f| f[%r{^spec/huginn}] }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", ">= 2.1.0"
  spec.add_development_dependency "rake", "~> 12.3.3"

  spec.add_runtime_dependency "huginn_agent"
end
