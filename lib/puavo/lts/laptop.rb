module Puavo
  module Lts
    class Laptop < Base

      def initialize(organisation, school, device)
        @organisation = organisation
        @school = school
        @device = device
        puts "\n\n Device: #{@device.inspect}"


        @lts_data = {
          'LOCAL_APPS'           => 'False',
          'LOCALDEV'             => 'False',
          'LTSP_FATCLIENT'       => 'True',
          'NBD_SWAP'             => 'False',
          'SCREEN_07'            => 'lightdm',
          'SYSLOG'               => 'False',
          'XKBLAYOUT'            => 'fi',
        }
        
        @lts_data.merge!( define_tags )
        @lts_data.merge!( define_default_printer )
        # FIXME
        # @lts_data.merge( define_xserver )
        @lts_data.merge!( define_xrandr_disable )
        @lts_data.merge!( define_system_services )

      end

    end
  end
end
