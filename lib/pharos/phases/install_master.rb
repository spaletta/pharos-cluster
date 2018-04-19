# frozen_string_literal: true

module Pharos
  module Phases
    class InstallMaster < Pharos::Phase
      title "Install master"

      KUBE_PKI_DIR = '/etc/kubernetes/pki'
      SHARED_CERT_FILES = %w(ca.crt ca.key sa.key sa.pub).freeze

      def kubeadm_config
        @kubeadm_config ||= Pharos::Kubeadm::Config.new(@config, @host)
      end

      def install?
        !@ssh.file("/etc/kubernetes/admin.conf").exist?
      end

      def call
        return unless install?

        push_certs if cluster_context['master-certs']
        install
        pull_certs unless cluster_context['master-certs']
      end

      def install
        cfg = kubeadm_config.generate

        logger.info { "Initializing control plane ..." }
        @ssh.tempfile(content: cfg.to_yaml, prefix: "kubeadm.cfg") do |tmp_file|
          @ssh.exec!("sudo kubeadm init --ignore-preflight-errors all --skip-token-print --config #{tmp_file}")
        end
        logger.info { "Initialization of control plane succeeded!" }
      end

      # Copies certificates from memory to host
      def push_certs
        logger.info { "Pushing kube certificate authority files to host ..." }

        @ssh.exec!("sudo mkdir -p #{KUBE_PKI_DIR}")
        cluster_context['master-certs'].each do |file, contents|
          path = File.join(KUBE_PKI_DIR, file)
          @ssh.file(path).write(contents)
          @ssh.exec!("sudo chmod 0400 #{path}")
        end
      end

      # Cache certs to memory
      def pull_certs
        logger.info { "Caching kube certificate authority files to memory ..." }

        cache = {}
        SHARED_CERT_FILES.each do |file|
          path = File.join(KUBE_PKI_DIR, file)
          cache[file] = @ssh.file(path).read
        end
        cluster_context['master-certs'] = cache
      end
    end
  end
end
