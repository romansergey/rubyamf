require 'rocketamf'
require 'active_support/inflector'
require 'active_support/core_ext/array'
require 'rubyamf/version'
require 'rubyamf/logger'
require 'rubyamf/fault'
require 'rubyamf/intermediate_object'
require 'rubyamf/class_mapping'
require 'rubyamf/serialization'
require 'rubyamf/configuration'
require 'rubyamf/envelope'
require 'rubyamf/request_parser'
require 'rubyamf/request_processor'

module RubyAMF
  MIME_TYPE = "application/x-amf".freeze

  # Put in module and use extend so that others can easily override
  # methods while still being able to call down to the original
  # through super
  module ClassMethods
    def configuration
      @configuration ||= RubyAMF::Configuration.new
    end

    def configuration= config
      @configuration = config
    end

    def logger
      @logger ||= RubyAMF::Logger.new
    end

    def configure
      yield configuration
      bootstrap
    end

    def bootstrap
      configuration.preload_models.flatten.each {|m| m.to_s.constantize}
      RubyAMF::ClassMapper.use_array_collection = configuration.use_array_collection # Make sure it gets copied over for RocketAMF
      RubyAMF::Serialization.load_support
    end

    def const_missing const #:nodoc:
      if const == :ClassMapper
        class_mapper = configuration.class_mapper
        RubyAMF.const_set(:ClassMapper, class_mapper)
        RocketAMF.const_set(:ClassMapper, class_mapper)
      else
        super(const)
      end
    end
  end
  extend ClassMethods
end

# Rails specific bootstrapping
if defined?(Rails)
  if Rails::VERSION::MAJOR == 3
    require 'rubyamf/rails/rails3_bootstrap'
  elsif Rails::VERSION::MAJOR == 2 && Rails::VERSION::MINOR >= 3
    require 'rubyamf/rails/rails2_bootstrap'
  else
    puts "unsupported rails version"
  end
end