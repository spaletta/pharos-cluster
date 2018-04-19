# frozen_string_literal: true

module Pharos
  module Phases
    class ConfigureClient < Pharos::Phase
      title "Configure kube client"

      def call
        install_local_kubeconfig(read_kubeconfig)
        install_remote_kubeconfig
      end

      def config_dir
        File.join(Dir.home, '.pharos')
      end

      def read_kubeconfig
        logger.info { "Fetching kubectl config ..." }
        config_data = @ssh.file("/etc/kubernetes/admin.conf").read
        config_data = config_data.gsub(%r{(server: https://)(.+)(:6443)}, "\\1#{@host.api_address}\\3")
      end

      def install_local_kubeconfig(config_data)
        Dir.mkdir(config_dir, 0o700) unless Dir.exist?(config_dir)

        config_file = File.join(config_dir, @host.api_address)

        logger.info { "Saving kubeconfig to #{config_file} ..." }

        File.chmod(0o600, config_file) if File.exist?(config_file)
        File.write(config_file, config_data, perm: 0o600)
      end

      def install_remote_kubeconfig
        logger.info { "Configuring remote kubectl ..." }

        @ssh.exec!('install -m 0700 -d ~/.kube')
        @ssh.exec!('sudo install -o $USER -m 0600 /etc/kubernetes/admin.conf ~/.kube/config')
      end
    end
  end
end
