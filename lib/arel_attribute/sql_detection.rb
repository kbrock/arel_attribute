module ArelAttribute
  module SqlDetection
    def self.included(base)
      base.extend ClassMethods
      # base.include InstanceMethods
    end

    module ClassMethods
      def is_pg?
        %w[postgresql pg].include?(connection.adapter_name.downcase)
      end
    end
  end
end
