# frozen_string_literal: true

module Pharos
  module Kubeadm
    class Config
      ETCD_CERT_DIR = '/etc/pharos/etcd'

      AUTHENTICATION_TOKEN_WEBHOOK_CERT_DIR = '/etc/pharos/token_webhook'
      AUTHENTICATION_TOKEN_WEBHOOK_CONFIG_DIR = '/etc/kubernetes/authentication'

      AUDIT_CFG_DIR = '/etc/pharos/audit'

      SECRETS_CFG_DIR = '/etc/pharos/secrets-encryption'
      SECRETS_CFG_FILE = SECRETS_CFG_DIR + '/config.yml'

      CLOUD_CFG_DIR = '/etc/pharos/cloud'
      CLOUD_CFG_FILE = CLOUD_CFG_DIR + '/cloud-config'

      # @param config [Pharos::Config]
      # @param host [Pharos::Configuration::Host]
      def initialize(config, host)
        @config = config
        @host = host
      end

      # @return [Hash]
      def generate_config
        config = {
          'apiVersion' => 'kubeadm.k8s.io/v1alpha1',
          'kind' => 'MasterConfiguration',
          'nodeName' => @host.hostname,
          'kubernetesVersion' => Pharos::KUBE_VERSION,
          'api' => {
            'advertiseAddress' => @host.peer_address,
            'controlPlaneEndpoint' => 'localhost'
          },
          'apiServerCertSANs' => build_extra_sans,
          'networking' => {
            'serviceSubnet' => @config.network.service_cidr,
            'podSubnet' => @config.network.pod_network_cidr
          },
          'controllerManagerExtraArgs' => {
            'horizontal-pod-autoscaler-use-rest-clients' => 'false'
          }
        }

        config['apiServerExtraArgs'] = {
          'apiserver-count' => @config.master_hosts.size.to_s
        }

        if @host.container_runtime == 'cri-o'
          config['criSocket'] = '/var/run/crio/crio.sock'
        end

        if @config.cloud && @config.cloud.provider != 'external'
          config['cloudProvider'] = @config.cloud.provider
          config['apiServerExtraArgs']['cloud-config'] = CLOUD_CFG_FILE if @config.cloud.config
        end

        # Only configure etcd if the external endpoints are given
        if @config.etcd&.endpoints
          configure_external_etcd(config)
        else
          configure_internal_etcd(config)
        end

        config['apiServerExtraVolumes'] = []

        # Only if authentication token webhook option are given
        configure_token_webhook(config) if @config.authentication&.token_webhook

        # Configure audit related things if needed
        configure_audit_webhook(config) if @config.audit&.server

        # Set secrets config location and mount it to api server
        config['apiServerExtraArgs']['experimental-encryption-provider-config'] = SECRETS_CFG_FILE
        config['apiServerExtraVolumes'] << {
          'name' => 'k8s-secrets-config',
          'hostPath' => SECRETS_CFG_DIR,
          'mountPath' => SECRETS_CFG_DIR
        }

        config
      end

      # @return [Array<String>]
      def build_extra_sans
        extra_sans = Set.new(['localhost'])
        extra_sans << @host.address
        extra_sans << @host.private_address if @host.private_address
        extra_sans << @host.api_endpoint if @host.api_endpoint

        extra_sans.to_a
      end

      # @param config [Pharos::Config]
      def configure_internal_etcd(config)
        endpoints = @config.etcd_hosts.map { |h|
          "https://#{h.peer_address}:2379"
        }
        config['etcd'] = {
          'endpoints' => endpoints
        }

        config['etcd']['certFile'] = '/etc/pharos/pki/etcd/client.pem'
        config['etcd']['caFile'] = '/etc/pharos/pki/ca.pem'
        config['etcd']['keyFile'] = '/etc/pharos/pki/etcd/client-key.pem'
      end

      def etcd_cert_dir
        ETCD_CERT_DIR
      end

      # @param config [Hash]
      def configure_external_etcd(config)
        config['etcd'] = {
          'endpoints' => @config.etcd.endpoints
        }

        config['etcd']['certFile'] = etcd_cert_dir + '/certificate.pem' if @config.etcd.certificate
        config['etcd']['caFile'] = etcd_cert_dir + '/ca-certificate.pem' if @config.etcd.ca_certificate
        config['etcd']['keyFile'] = etcd_cert_dir + '/certificate-key.pem' if @config.etcd.key
      end

      # @param config [Hash]
      def configure_token_webhook(config)
        config['apiServerExtraArgs'].merge!(authentication_token_webhook_args(@config.authentication.token_webhook.cache_ttl))
        config['apiServerExtraVolumes'] += volume_mounts_for_authentication_token_webhook
      end

      def audit_dir
        AUDIT_CFG_DIR
      end

      def audit_webhook_config_file
        AUDIT_CFG_DIR + '/webhook.yml'
      end

      def audit_policy_file
        AUDIT_CFG_DIR + '/policy.yml'
      end

      # @param config [Hash]
      def configure_audit_webhook(config)
        config['apiServerExtraArgs'].merge!(
          "audit-webhook-config-file" => audit_webhook_config_file,
          "audit-policy-file" => audit_policy_file
        )
        config['apiServerExtraVolumes'] += volume_mounts_for_audit_webhook
      end

      def volume_mounts_for_audit_webhook
        volume_mounts = []
        volume_mounts << {
          'name' => 'k8s-audit-webhook',
          'hostPath' => audit_dir,
          'mountPath' => audit_dir
        }
        volume_mounts
      end

      def authentication_token_webhook_config_dir
        AUTHENTICATION_TOKEN_WEBHOOK_CONFIG_DIR
      end

      def authentication_token_webhook_config_file
        AUTHENTICATION_TOKEN_WEBHOOK_CONFIG_DIR + '/token-webhook-config.yaml'
      end

      def authentication_token_webhook_cert_dir
        AUTHENTICATION_TOKEN_WEBHOOK_CERT_DIR
      end

      # @param webhook_config [Hash]
      def generate_authentication_token_webhook_config(webhook_config)
        config = {
          "kind" => "Config",
          "apiVersion" => "v1",
          "preferences" => {},
          "clusters" => [
            {
              "name" => webhook_config[:cluster][:name].to_s,
              "cluster" => {
                "server" => webhook_config[:cluster][:server].to_s
              }
            }
          ],
          "users" => [
            {
              "name" => webhook_config[:user][:name].to_s,
              "user" => {}
            }
          ],
          "contexts" => [
            {
              "name" => "webhook",
              "context" => {
                "cluster" => webhook_config[:cluster][:name].to_s,
                "user" => webhook_config[:user][:name].to_s
              }
            }
          ],
          "current-context" => "webhook"
        }

        if webhook_config[:cluster][:certificate_authority]
          config['clusters'][0]['cluster']['certificate-authority'] = authentication_token_webhook_cert_dir + '/ca.pem'
        end

        if webhook_config[:user][:client_certificate]
          config['users'][0]['user']['client-certificate'] = authentication_token_webhook_cert_dir + '/cert.pem'
        end

        if webhook_config[:user][:client_key]
          config['users'][0]['user']['client-key'] = authentication_token_webhook_cert_dir + '/key.pem'
        end

        config
      end

      def authentication_token_webhook_args(cache_ttl = nil)
        config = {
          'authentication-token-webhook-config-file' => authentication_token_webhook_config_file
        }
        config['authentication-token-webhook-cache-ttl'] = cache_ttl if cache_ttl
        config
      end

      def volume_mounts_for_authentication_token_webhook
        volume_mounts = []
        volume_mounts << {
          'name' => 'k8s-auth-token-webhook',
          'hostPath' => AUTHENTICATION_TOKEN_WEBHOOK_CONFIG_DIR,
          'mountPath' => AUTHENTICATION_TOKEN_WEBHOOK_CONFIG_DIR
        }
        volume_mounts << {
          'name' => 'pharos-auth-token-webhook-certs',
          'hostPath' => AUTHENTICATION_TOKEN_WEBHOOK_CERT_DIR,
          'mountPath' => AUTHENTICATION_TOKEN_WEBHOOK_CERT_DIR
        }
        volume_mounts
      end

      def cloud_cfg_dir
        CLOUD_CFG_DIR
      end
      def cloud_cfg_file
        CLOUD_CFG_FILE
      end
    end
  end
end
