module RubyAMF
  module Model
    def self.included base
      base.send :extend, ClassMethods
    end

    module ClassMethods
      def as_class class_name
        @as_class = class_name.to_s
        RubyAMF::ClassMapper.mappings.map :as => @as_class, :ruby => self.name
      end
      alias :actionscript_class :as_class
      alias :flash_class :as_class
      alias :amf_class :as_class

      def map_amf scope_or_options=nil, options=nil
        # Make sure they've already called as_class first
        raise "Must define as_class first" unless @as_class

        # Format parameters to pass to RubyAMF::MappingSet#map
        if options
          options[:scope] = scope_or_options
        else
          options = scope_or_options
        end
        options[:as] = @as_class
        options[:ruby] = self.name
        RubyAMF::ClassMapper.mappings.map options
      end
    end

    def rubyamf_init props, dynamic_props = nil
      raise "Must implement attributes= method for default rubyamf_init to work" unless respond_to?(:attributes=)

      initialize # warhammerkid: Call initialize by default - good decision?

      attrs = self.attributes
      props.merge!(dynamic_props) if dynamic_props
      not_attributes = props.keys.select {|k| !attrs.include?(k)}

      not_attributes.each do |k|
        setter = "#{k}="
        next if setter !~ /^[a-z][A-Za-z0-9_]+=/ # Make sure setter doesn't start with capital, dollar, or underscore to make this safer
        send(setter, props.delete(k)) if respond_to?(setter)
      end
      self.attributes = props # Populate using attributes setter
    end

    def rubyamf_hash options=nil
      raise "Must implement attributes method for rubyamf_hash to work" unless respond_to?(:attributes)

      # Process options
      options ||= {}
      only = Array.wrap(options[:only]).map(&:to_s)
      except = Array.wrap(options[:except]).map(&:to_s)
      method_names = []
      Array.wrap(options[:methods]).each do |name|
        method_names << name.to_s if respond_to?(name)
      end

      # Get list of attributes
      saved_attributes = attributes
      attribute_names = saved_attributes.keys.sort
      if only.any?
        attribute_names &= only
      elsif except.any?
        attribute_names -= except
      end

      # Remove ignore_fields unless in only
      RubyAMF.configuration.ignore_fields.each do |field|
        attribute_names.delete(field) unless only.include?(field)
      end

      # Build hash from attributes and methods
      hash = {}
      attribute_names.each {|name| hash[name] = saved_attributes[name]}
      method_names.each {|name| hash[name] = send(name)}

      # Add associations using ActiveRecord::Serialization style options
      # processing
      if include_associations = options.delete(:include)
        # Process options
        base_only_or_except = {:except => options[:except], :only => options[:only]}
        include_has_options = include_associations.is_a?(Hash)
        associations = include_has_options ? include_associations.keys : Array.wrap(include_associations)

        # Call to_amf on each object in the association, passing processed options
        associations.each do |association|
          records = rubyamf_retrieve_association(association)
          if records
            opts = include_has_options ? include_associations[association] : nil
            if records.is_a?(Enumerable)
              hash[association.to_s] = records.map {|r| opts.nil? ? r : r.to_amf(opts)}
            else
              hash[association.to_s] = opts.nil? ? records : records.to_amf(opts)
            end
          end
        end

        options[:include] = include_associations
      end

      hash
    end

    def rubyamf_retrieve_association association
      # Naive implementation that should work for most cases without
      # need for overriding
      send(association)
    end

    def to_amf options=nil
      RubyAMF::IntermediateObject.new(self, options)
    end
  end
end

# Map array to_amf calls to each element
class Array
  def to_amf options=nil
    self.map {|o| o.to_amf(options)}
  end
end