module ArelAttribute
  module SqlDetection
    def self.included(base)
      base.extend ClassMethods
      # base.include InstanceMethods
    end

    module ClassMethods
      def is_pg?(*args)
        ret=%w[postgresql pg].include?(connection.adapter_name.downcase)
        if args.empty?
          ret
        else
          ret ? args.first : args.last
        end
      end

      def is_mysql?(*args)
        ret = %w[mysql mysql2 trillian].include?(connection.adapter_name.downcase)
        if args.empty?
          ret
        else
          ret ? args.first : args.last
        end
      end

      def is_sqlite?(*args)
        ret = %w[sqlite3 sqlite].include?(connection.adapter_name.downcase)
        if args.empty?
          ret
        else
          ret ? args.first : args.last
        end
      end
    end
  end
end
