# frozen_string_literal: true

module Pharos
  module Phases
    class ConfigureHost < Pharos::Phase
      title "Configure hosts"

      def call
        logger.info { "Configuring script helpers ..." }
        host_configurer.configure_script_library

        logger.info { "Configuring essential packages ..." }
        host_configurer.install_essentials

        logger.info { "Configuring package repositories ..." }
        host_configurer.configure_repos

        logger.info { "Configuring netfilter ..." }
        host_configurer.configure_netfilter

        logger.info { "Configuring container runtime (#{@host.container_runtime}) packages ..." }
        host_configurer.configure_container_runtime
      end
    end
  end
end
