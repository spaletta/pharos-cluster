require 'pharos/phases/migrate_master'

describe Pharos::Phases::MigrateMaster do
  let(:host) { instance_double(Pharos::Configuration::Host) }
  let(:ssh) { instance_double(Pharos::SSH::Client) }
  subject { described_class.new(host, ssh: ssh) }
end