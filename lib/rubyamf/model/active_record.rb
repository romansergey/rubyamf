module RubyAMF::Model
  module ActiveRecord
    def rubyamf_init props, dynamic_props = nil
      # Convert props and dynamic props to hash with string keys for attributes
      attrs = {}
      props.each {|k,v| attrs[k.to_s] = v}
      dynamic_props.each {|k,v| attrs[k.to_s] = v} unless dynamic_props.nil?

      # Is it a new record or existing? - support composite primary keys just in case
      is_new = true
      pk = Array.wrap(self.class.primary_key).map &:to_s
      if pk.length > 1 || pk[0] != 'id'
        unless pk.any? {|k| attrs[k].nil?}
          search = pk.map {|k| attrs[k]}
          search = search.first if search.length == 1
          is_new = !self.class.exists?(search) # Look it up in the database to make sure because it may be a string PK (or composite PK)
        end
      else
        is_new = false unless attrs['id'] == 0 || attrs['id'] == nil
      end

      if is_new
        # Call initialize to populate everything for a new object
        self.send(:initialize)
      else
        # Initialize with defaults so that changed properties will be marked dirty
        pk_attrs = pk.inject({}) {|h, k| h[k] = attrs[k]; h}
        base_attrs = self.send(:attributes_from_column_definition).merge(pk_attrs)

        if ::ActiveRecord::VERSION::MAJOR == 2
          # if rails 2, use code from ActiveRecord::Base#instantiate (just copied it over)
          object = self
          object.instance_variable_set("@attributes", base_attrs)
          object.instance_variable_set("@attributes_cache", Hash.new)

          if object.respond_to_without_attributes?(:after_find)
            object.send(:callback, :after_find)
          end

          if object.respond_to_without_attributes?(:after_initialize)
            object.send(:callback, :after_initialize)
          end
        else
          # if rails 3, use init_with('attributes' => attributes_hash)
          self.init_with('attributes' => base_attrs)
        end
      end

      # Delete pk from attrs and set attributes
      pk.each {|k| attrs.delete(k)}
      self.send(:attributes=, attrs)

      self
    end

    def rubyamf_hash options=nil
      return super(options) unless RubyAMF.configuration.check_for_associations

      options ||= {}

      # Iterate through assocations and check to see if they are loaded
      auto_include = []
      self.class.reflect_on_all_associations.each do |reflection|
        next if reflection.macro == :belongs_to # Skip belongs_to to prevent recursion
        is_loaded = if self.respond_to?(:association)
          # Rails 3.1
          self.association(reflection.name).loaded?
        elsif self.respond_to?("loaded_#{reflection.name}?")
          # Rails 2.3 and 3.0 for some types
          send("loaded_#{reflection.name}?")
        else
          # Rails 2.3 and 3.0 for some types
          send(reflection.name).loaded?
        end
        auto_include << reflection.name if is_loaded
      end

      # Add these assocations to the :include if they are not already there
      if include_associations = options.delete(:include)
        if include_associations.is_a?(Hash)
          auto_include.each {|assoc| include_associations[assoc] ||= {}}
        else
          include_associations = Array.wrap(include_associations) | auto_include
        end
        options[:include] = include_associations
      else
        options[:include] = auto_include if auto_include.length > 0
      end

      super(options)
    end

    def rubyamf_retrieve_association association
      case self.class.reflect_on_association(association).macro
      when :has_many, :has_and_belongs_to_many
        send(association).to_a
      when :has_one, :belongs_to
        send(association)
      end
    end
  end
end

class ActiveRecord::Base
  include RubyAMF::Model
  include RubyAMF::Model::ActiveRecord
end