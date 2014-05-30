require 'socket'
require 'ostruct'

module Fluent
  class RemoveEmptyOutput < Output
    Fluent::Plugin.register_output('remove_empty', self)

    def initialize
      super
    end

    config_param :tag, :string, :default => nil

    BUILTIN_CONFIGURATIONS = %W(type tag)

    # To support log_level option implemented by Fluentd v0.10.43
    unless method_defined?(:log)
      define_method("log") { $log }
    end

    def configure(conf)
      super

      @map = {}
      conf.each_pair { |k, v|
        next if BUILTIN_CONFIGURATIONS.include?(k)
        conf.has_key?(k) # to suppress unread configuration warning
        @map[k] = v
      }

      if @tag.nil?
        raise Fluent::ConfigError, "out_remove_empty: `tag` must be specified"
      end
      
      @placeholder_expander =
      if @enable_ruby
          # require utilities which would be used in ruby placeholders
          require 'pathname'
          require 'uri'
          require 'cgi'
          RubyPlaceholderExpander.new(log)
          else
          PlaceholderExpander.new(log)
      end
      
      @hostname = Socket.gethostname
    end

    def emit(tag, es, chain)
      tag_parts = tag.split('.')
      tag_prefix = tag_prefix(tag_parts)
      tag_suffix = tag_suffix(tag_parts)
      placeholders = {
        'tag' => tag,
        'tags' => tag_parts,
        'tag_parts' => tag_parts,
        'tag_prefix' => tag_prefix,
        'tag_suffix' => tag_suffix,
        'hostname' => @hostname,
      }
      last_record = nil
      es.each {|time, record|
        last_record = record # for debug log
        new_tag, new_record = reform(@tag, time, record, placeholders)
        Engine.emit(new_tag, time, new_record)
      }
      chain.next
    rescue => e
      log.warn "remove_empty: #{e.class} #{e.message} #{e.backtrace.first}"
      log.debug "remove_empty: tag:#{@tag} map:#{@map} record:#{last_record} placeholders:#{placeholders}"
    end

    private

    def reform(tag, time, record, opts)
      @placeholder_expander.prepare_placeholders(time, record, opts)
      new_tag = @placeholder_expander.expand(tag)

      new_record = record.dup
      new_record.each_key do |k|
        if new_record[k] == ""
          new_record.delete(k)
        end
      end

      [new_tag, new_record]
    end

    def tag_prefix(tag_parts)
      return [] if tag_parts.empty?
      tag_prefix = [tag_parts.first]
      1.upto(tag_parts.size-1).each do |i|
        tag_prefix[i] = "#{tag_prefix[i-1]}.#{tag_parts[i]}"
      end
      tag_prefix
    end

    def tag_suffix(tag_parts)
      return [] if tag_parts.empty?
      rev_tag_parts = tag_parts.reverse
      rev_tag_suffix = [rev_tag_parts.first]
      1.upto(tag_parts.size-1).each do |i|
        rev_tag_suffix[i] = "#{rev_tag_parts[i]}.#{rev_tag_suffix[i-1]}"
      end
      rev_tag_suffix.reverse
    end

    class PlaceholderExpander
      attr_reader :placeholders, :log

      def initialize(log)
        @log = log
      end

      def prepare_placeholders(time, record, opts)
        placeholders = { '${time}' => Time.at(time).to_s }
        record.each {|key, value| placeholders.store("${#{key}}", value) }

        opts.each do |key, value|
          if value.kind_of?(Array) # tag_parts, etc
            size = value.size
            value.each_with_index { |v, idx|
              placeholders.store("${#{key}[#{idx}]}", v)
              placeholders.store("${#{key}[#{idx-size}]}", v) # support [-1]
            }
          else # string, interger, float, and others?
            placeholders.store("${#{key}}", value)
          end
        end

        @placeholders = placeholders
      end

      def expand(str)
        str.gsub(/(\${[a-z_]+(\[-?[0-9]+\])?}|__[A-Z_]+__)/) {
          log.warn "remove_empty: unknown placeholder `#{$1}` found" unless @placeholders.include?($1)
          @placeholders[$1]
        }
      end
    end

    class RubyPlaceholderExpander
      attr_reader :placeholders, :log

      def initialize(log)
        @log = log
      end

      # Get placeholders as a struct
      #
      # @param [Time]   time        the time
      # @param [Hash]   record      the record
      # @param [Hash]   opts        others
      def prepare_placeholders(time, record, opts)
        struct = UndefOpenStruct.new(record)
        struct.time = Time.at(time)
        opts.each {|key, value| struct.__send__("#{key}=", value) }
        @placeholders = struct
      end

      # Replace placeholders in a string
      #
      # @param [String] str         the string to be replaced
      def expand(str)
        str = str.gsub(/\$\{([^}]+)\}/, '#{\1}') # ${..} => #{..}
        eval "\"#{str}\"", @placeholders.instance_eval { binding }
      end

      class UndefOpenStruct < OpenStruct
        (Object.instance_methods).each do |m|
          undef_method m unless m.to_s =~ /^__|respond_to_missing\?|object_id|public_methods|instance_eval|method_missing|define_singleton_method|respond_to\?|new_ostruct_member/
        end
      end
    end
  end
end
