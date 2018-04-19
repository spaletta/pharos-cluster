# frozen_string_literal: true

module Pharos
  module Phases
    class UpgradeMaster < Pharos::Phase
      title "Upgrade master"

      def kubeadm_config
        @kubeadm_config ||= Pharos::Kubeadm::Config.new(@config, @host)
      end

      def upgrade?
        file = @ssh.file('/etc/kubernetes/manifests/kube-apiserver.yaml')

        return false unless file.exist?
        return false if file.read.match?(/kube-apiserver-.+:v#{Pharos::KUBE_VERSION}/)

        true
      end

      def call
        return unless upgrade?

        upgrade_kubeadm
        upgrade
      end

      def upgrade_kubeadm
        logger.info { "Upgrading kubeadm ..." }

        exec_script(
          "install-kubeadm.sh",
          VERSION: Pharos::KUBEADM_VERSION,
          ARCH: @host.cpu_arch.name
        )
      end

      def upgrade
        cfg = kubeadm_config.generate

        logger.info { "Upgrading control plane ..." }
        @ssh.tempfile(content: cfg.to_yaml, prefix: "kubeadm.cfg") do |tmp_file|
          @ssh.exec!("sudo kubeadm upgrade apply #{Pharos::KUBE_VERSION} -y --ignore-preflight-errors=all --allow-experimental-upgrades --config #{tmp_file}")
        end
        logger.info { "Control plane upgrade succeeded!" }
      end
    end
  end
end
