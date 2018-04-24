require "pharos/kubeadm"

describe Pharos::Kubeadm::Config do
  let(:host) { Pharos::Configuration::Host.new(address: '192.0.2.1', private_address: '192.168.0.1', role: 'master') }
  let(:config_hosts_count) { 1 }

  let(:config) { Pharos::Config.new(
      hosts: (1..config_hosts_count).map { |i| Pharos::Configuration::Host.new(role: 'worker') },
      network: {
        service_cidr: '1.2.3.4/16',
        pod_network_cidr: '10.0.0.0/16'
      },
      addons: {},
      etcd: {}
  ) }

  subject { described_class.new(config, host) }

  describe '#generate_config' do
    context 'with auth configuration' do
      let(:config) { Pharos::Config.new(
        hosts: (1..config_hosts_count).map { |i| Pharos::Configuration::Host.new() },
        network: {},
        addons: {},
        audit: {
          server: 'foobar'
        }
      ) }

      it 'comes with proper audit config' do
        config = subject.generate_config
        expect(config.dig('apiServerExtraArgs', 'audit-webhook-config-file')).to eq('/etc/pharos/audit/webhook.yml')
        expect(config.dig('apiServerExtraVolumes')).to include({
          'name' => 'k8s-audit-webhook',
          'hostPath' => '/etc/pharos/audit',
          'mountPath' => '/etc/pharos/audit'
        })
      end
    end

    context 'with network configuration' do
      let(:config) { Pharos::Config.new(
        hosts: (1..config_hosts_count).map { |i| Pharos::Configuration::Host.new() },
        network: {
          service_cidr: '1.2.3.4/16',
          pod_network_cidr: '10.0.0.0/16'
        },
        addons: {},
        etcd: {}
      ) }

      it 'comes with correct subnets' do
        config = subject.generate_config
        expect(config.dig('networking', 'serviceSubnet')).to eq('1.2.3.4/16')
        expect(config.dig('networking', 'podSubnet')).to eq('10.0.0.0/16')
      end

    end

    it 'comes with correct master addresses' do
      config.hosts << host
      config = subject.generate_config
      expect(config.dig('apiServerCertSANs')).to eq(['localhost', '192.0.2.1', '192.168.0.1'])
      expect(config.dig('api', 'advertiseAddress')).to eq('192.168.0.1')
    end

    it 'comes with internal etcd config' do
      config = subject.generate_config
      expect(config.dig('etcd')).not_to be_nil
      expect(config.dig('etcd', 'endpoints')).not_to be_nil
      expect(config.dig('etcd', 'version')).to be_nil
    end

    it 'comes with secrets encryption config' do
      config = subject.generate_config
      expect(config.dig('apiServerExtraArgs', 'experimental-encryption-provider-config')).to eq(described_class::SECRETS_CFG_FILE)
      expect(config['apiServerExtraVolumes']).to include({'name' => 'k8s-secrets-config',
        'hostPath' => described_class::SECRETS_CFG_DIR,
        'mountPath' => described_class::SECRETS_CFG_DIR
      })
    end

    context 'with etcd endpoint configuration' do
      let(:config) { Pharos::Config.new(
        hosts: (1..config_hosts_count).map { |i| Pharos::Configuration::Host.new() },
        network: {},
        addons: {},
        etcd: {
          endpoints: ['ep1', 'ep2']
        }
      ) }

      it 'comes with proper etcd endpoint config' do
        config = subject.generate_config
        expect(config.dig('etcd', 'endpoints')).to eq(['ep1', 'ep2'])
      end
    end

    context 'with etcd certificate configuration' do

      let(:config) { Pharos::Config.new(
        hosts: (1..config_hosts_count).map { |i| Pharos::Configuration::Host.new() },
        network: {},
        addons: {},
        etcd: {
          endpoints: ['ep1', 'ep2'],
          ca_certificate: 'ca-certificate.pem',
          certificate: 'certificate.pem',
          key: 'key.pem'
        }
      ) }

      it 'comes with proper etcd certificate config' do
        config = subject.generate_config
        expect(config.dig('etcd', 'caFile')).to eq('/etc/pharos/etcd/ca-certificate.pem')
        expect(config.dig('etcd', 'certFile')).to eq('/etc/pharos/etcd/certificate.pem')
        expect(config.dig('etcd', 'keyFile')).to eq('/etc/pharos/etcd/certificate-key.pem')
      end
    end

    context 'with cloud configuration' do
      let(:config) { Pharos::Config.new(
        hosts: (1..config_hosts_count).map { |i| Pharos::Configuration::Host.new() },
        network: {},
        addons: {},
        cloud: {
          provider: 'aws',
          config: './cloud-config'
        }
      ) }

      it 'comes with proper cloud provider' do
        config = subject.generate_config
        expect(config['cloudProvider']).to eq('aws')
      end

      it 'comes with proper cloud config' do
        config = subject.generate_config
        expect(config.dig('apiServerExtraArgs', 'cloud-config')).to eq('/etc/pharos/cloud/cloud-config')
      end
    end

    context 'with authentication webhook configuration' do
      let(:config) { Pharos::Config.new(
        hosts: (1..config_hosts_count).map { |i| Pharos::Configuration::Host.new() },
        network: {},
        addons: {},
        authentication: {
          token_webhook: {
            config: {
              cluster: {
                name: 'pharos-authn',
                server: 'http://localhost:9292/token'
              },
              user: {
                name: 'pharos-apiserver'
              }
            }
          }
        }
      ) }

      it 'comes with proper authentication webhook token config' do
        config = subject.generate_config
        expect(config['apiServerExtraArgs']['authentication-token-webhook-config-file'])
          .to eq('/etc/kubernetes/authentication/token-webhook-config.yaml')
      end

      it 'comes with proper volume mounts' do
        valid_volume_mounts =  [
          {
            'name' => 'k8s-auth-token-webhook',
            'hostPath' => '/etc/kubernetes/authentication',
            'mountPath' => '/etc/kubernetes/authentication'
          },
          {
            'name' => 'pharos-auth-token-webhook-certs',
            'hostPath' => '/etc/pharos/token_webhook',
            'mountPath' => '/etc/pharos/token_webhook'
          }
        ]
        config = subject.generate_config
        expect(config['apiServerExtraVolumes']).to include(valid_volume_mounts[0])
      end
    end

    context 'with cri-o configuration' do
      let(:host) { Pharos::Configuration::Host.new(address: 'test', container_runtime: 'cri-o') }
      let(:config) { Pharos::Config.new(
        hosts: (1..config_hosts_count).map { |i| Pharos::Configuration::Host.new() },
        network: {},
        addons: {},
        etcd: {}
      ) }

      it 'comes with proper etcd endpoint config' do
        config = subject.generate_config
        expect(config.dig('criSocket')).to eq('/var/run/crio/crio.sock')
      end
    end

    context 'with multiple masters' do
      let(:config) { Pharos::Config.new(
        hosts: (1..3).map { |i| Pharos::Configuration::Host.new(role: 'master') },
        network: {},
        addons: {},
        etcd: {}
      ) }

      it 'comes with proper apiserver-count' do
        config = subject.generate_config
        expect(config.dig('apiServerExtraArgs', 'apiserver-count')).to eq("3")
      end
    end
  end

  describe '#generate_authentication_token_webhook_config' do
    let(:webhook_config) do
      {
        cluster: {
          name: 'pharos-authn',
          server: 'http://localhost:9292/token'
        },
        user: {
          name: 'pharos-apiserver'
        }
      }
    end

    it 'comes with proper configuration' do
      valid_config =  {
        "kind" => "Config",
        "apiVersion" => "v1",
        "preferences" => {},
        "clusters" => [
            {
                "name" => "pharos-authn",
                "cluster" => {
                    "server" => "http://localhost:9292/token",
                }
            }
        ],
        "users" => [
            {
                "name" => "pharos-apiserver",
                "user" => {}
            }
        ],
        "contexts" => [
            {
                "name" => "webhook",
                "context" => {
                    "cluster" => "pharos-authn",
                    "user" => "pharos-apiserver"
                }
            }
        ],
        "current-context" => "webhook"
      }
      expect(subject.generate_authentication_token_webhook_config(webhook_config))
        .to eq(valid_config)
    end

    context 'with cluster certificate_authority' do
      it 'adds certificate authority config' do
        webhook_config[:cluster][:certificate_authority] = '/etc/ca.pem'
        config = subject.generate_authentication_token_webhook_config(webhook_config)
        expect(config['clusters'][0]['cluster']['certificate-authority']).to eq('/etc/pharos/token_webhook/ca.pem')
      end
    end

    context 'with user client certificate' do
      it 'adds client certificate' do
        webhook_config[:user][:client_certificate] = '/etc/cert.pem'
        config = subject.generate_authentication_token_webhook_config(webhook_config)
        expect(config['users'][0]['user']['client-certificate']).to eq('/etc/pharos/token_webhook/cert.pem')
      end
    end

    context 'with user client key' do
      it 'adds client key' do
        webhook_config[:user][:client_key] = '/etc/key.pem'
        config = subject.generate_authentication_token_webhook_config(webhook_config)
        expect(config['users'][0]['user']['client-key']).to eq('/etc/pharos/token_webhook/key.pem')
      end
    end
  end
end
