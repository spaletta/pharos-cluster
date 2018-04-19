# frozen_string_literal: true

module Pharos
  module Phases
    class ConfigureMaster < Pharos::Phase
      title "Configure master"

      def kubeadm_config
        @kubeadm_config ||= Pharos::Kubeadm::Config.new(@config, @host)
      end

      def call
        push_external_etcd_certs if @config.etcd&.certificate

        push_audit_config if @config.audit&.server

        push_authentication_token_webhook_config if @config.authentication&.token_webhook
      end

      def push_external_etcd_certs
        logger.info { "Pushing external etcd certificates ..." }

        # TODO: lock down permissions on key
        @ssh.exec!("sudo mkdir -p #{kubeadm_config.etcd_cert_dir}")
        @ssh.file("#{kubeadm_config.etcd_cert_dir}/ca-certificate.pem").write(File.open(@config.etcd.ca_certificate))
        @ssh.file("#{kubeadm_config.etcd_cert_dir}/certificate.pem").write(File.open(@config.etcd.certificate))
        @ssh.file("#{kubeadm_config.etcd_cert_dir}/certificate-key.pem").write(File.open(@config.etcd.key))
      end

      def push_audit_config
        logger.info { "Pushing audit configs to master ..." }

        @ssh.exec!("sudo mkdir -p #{kubeadm_config.audit_dir}")
        @ssh.file(kubeadm_config.audit_webhook_config_file).write(
          parse_resource_file('audit/webhook-config.yml.erb', server: @config.audit.server)
        )
        @ssh.file(kubeadm_config.audit_policy_file).write(parse_resource_file('audit/policy.yml'))
      end

      # @param config [Hash]
      def upload_authentication_token_webhook_config(config)
        logger.info { "Pushing token authentication webhook config ..." }

        @ssh.exec!("sudo mkdir -p #{kubeadm_config.authentication_token_webhook_config_dir}")
        @ssh.file(kubeadm_config.authentication_token_webhook_config_file).write(config.to_yaml)
      end

      # @param webhook_config [Hash]
      def upload_authentication_token_webhook_certs(webhook_config)
        logger.info { "Pushing token authentication webhook certificates ..." }

        @ssh.exec!("sudo mkdir -p #{kubeadm_config.authentication_token_webhook_cert_dir}")
        @ssh.file(kubeadm_config.authentication_token_webhook_cert_dir + '/ca.pem').write(File.open(File.expand_path(webhook_config[:cluster][:certificate_authority]))) if webhook_config[:cluster][:certificate_authority]
        @ssh.file(kubeadm_config.authentication_token_webhook_cert_dir + '/cert.pem').write(File.open(File.expand_path(webhook_config[:user][:client_certificate]))) if webhook_config[:user][:client_certificate]
        @ssh.file(kubeadm_config.authentication_token_webhook_cert_dir + '/key.pem').write(File.open(File.expand_path(webhook_config[:user][:client_key]))) if webhook_config[:user][:client_key]
      end

      def push_authentication_token_webhook_config
        webhook_config = @config.authentication.token_webhook.config

        logger.debug { "Generating token authentication webhook config ..." }
        auth_token_webhook_config = kubeadm_config.generate_authentication_token_webhook_config(webhook_config)

        upload_authentication_token_webhook_config(auth_token_webhook_config)

        upload_authentication_token_webhook_certs(webhook_config)
      end
    end
  end
end
