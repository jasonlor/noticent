# frozen_string_literal: true

require 'spec_helper'

describe Noticent::Config do
  it 'is configured' do
    Noticent.configure {}
    expect(Noticent.configuration.opt_in_provider).not_to be_nil
  end

  it 'should be configurable' do
    ENV['NOTICENT_RSPEC'] = '0'
    Noticent.configure do |config|
      config.base_dir = 'foo'
      config.base_module_name = 'Noticent::Foo'
    end

    expect(Noticent.configuration.base_dir).to eq('foo')
    ENV['NOTICENT_RSPEC'] = '1'
  end

  it 'is a hash' do
    config = Noticent.configure { |_config| nil }
    expect(config).to be_a_kind_of(Noticent::Config)
  end

  it 'returns config' do
    Noticent.configure {}

    expect(Noticent.configuration).to be_a_kind_of(Noticent::Config)
  end

  it 'should have hooks' do
    hooks = nil
    Noticent.configure do |config|
      hooks = config.hooks
    end

    expect(hooks).not_to be_nil
    expect(hooks).to be_a_kind_of(Noticent::Definitions::Hooks)
  end

  it 'channel hooks should be addable' do
    Noticent.configure do |config|
      config.hooks.add(:pre_channel_registration, String)
      config.hooks.add(:post_channel_registration, Integer)
      config.hooks.add(:pre_channel_registration, Hash)
    end

    expect(Noticent.configuration.hooks).not_to be_nil
    expect(Noticent.configuration.hooks.send(:storage).count).to eq(2)
    expect(Noticent.configuration.hooks.send(:storage)[:pre_channel_registration].count).to eq(2)
    expect(Noticent.configuration.hooks.send(:storage)[:post_channel_registration].count).to eq(1)
    expect(Noticent.configuration.hooks.send(:storage)[:pre_channel_registration]).to include(String, Hash)
    expect(Noticent.configuration.hooks.send(:storage)[:post_channel_registration]).to include(Integer)
    expect(Noticent.configuration.hooks.fetch(:post_channel_registration)).to include(Integer)
    expect(Noticent.configuration.hooks.fetch(:pre_channel_registration)).to include(String, Hash)
    expect { Noticent.configuration.hooks.add(:bad_hook, String) }.to raise_error(Noticent::BadConfiguration)
  end

  it 'should have channel' do
    Noticent.configure do |config|
      config.channel(:email, klass: ::Noticent::Testing::Email) {}
    end
  end

  it 'should find channels by group' do
    Noticent.configure do |config|
      config.channel(:email) {}
      config.channel(:slack) {}
      config.channel(:webhook, group: :special) {}
    end

    expect(Noticent.configuration.channels_by_group(:default).count).to eq(2)
    expect(Noticent.configuration.channels_by_group(:special).count).to eq(1)
    expect(Noticent.configuration.channels_by_group(:wrong)).not_to be_nil
    expect(Noticent.configuration.channels_by_group(:wrong)).to be_empty
  end

  it 'should find channel groups' do
    Noticent.configure do
      channel :email
      channel :slack
      channel :webhook, group: :internal
      channel :boo, group: :internal
      channel :foo, group: :private
    end

    expect(Noticent.configuration.channels.count).to eq(5)
    expect(Noticent.configuration.channel_groups.count).to eq(3)
  end

  it 'should find alert channels' do
    Noticent.configure do
      channel :email
      channel :slack
      channel :webhook, group: :internal
      channel :boo, group: :internal
      channel :foo, group: :private

      scope :post do
        alert :foo do
          notify(:users).on(:default)
          notify(:owners).on(:internal)
        end

        alert :boo do
          notify(:users).on(:private)
        end
      end
    end

    expect(Noticent.configuration.alert_channels(:foo).map(&:name)).to eq(%i[email slack webhook boo])
    expect(Noticent.configuration.alert_channels(:boo).map(&:name)).to eq([:foo])
  end

  it 'should check for alert name methods on channel' do
    expect do
      Noticent.configure do
        channel :email
        channel :slack
        channel :webhook, group: :internal
        channel :boo, group: :internal
        channel :foo, group: :private

        scope :post do
          alert :bad_alert do
            notify(:users).on(:default)
            notify(:owners).on(:internal)
          end
        end
      end
    end.to raise_error Noticent::BadConfiguration
  end

  it 'should find alerts by scope' do
    Noticent.configure do
      scope :post do
        alert :one
        alert :two
      end

      scope :comment do
        alert :three
      end
    end

    expect(Noticent.configuration.alerts_by_scope(:post)).not_to be_nil
    expect(Noticent.configuration.alerts_by_scope(:post).count).to eq(2)
    expect(Noticent.configuration.alerts_by_scope(:post).map(&:name)).to eq(%i[one two])
    expect(Noticent.configuration.alerts_by_scope(:comment).map(&:name)).to eq([:three])
  end

  it 'should not allow duplicate channels' do
    expect do
      Noticent.configure do |config|
        config.channel(:email) {}
        config.channel(:foo) {}
        config.channel(:email) {}
      end
    end.to raise_error(Noticent::BadConfiguration, 'channel \'email\' already defined')
  end

  it 'should define a scope' do
    Noticent.configure do
      scope :post do
      end
    end
  end

  it 'should have scopes and alerts' do
    expect do
      Noticent.configure do
        scope :post do
          alert(:tfa_enabled) {}
          alert(:sign_up, tags: %i[foo bar]) {}
        end
      end
    end.not_to raise_error

    expect(Noticent.configuration.scopes).not_to be_nil
    expect(Noticent.configuration.scopes.count).to eq(1)
    expect(Noticent.configuration.scopes[:post]).not_to be_nil
    expect(Noticent.configuration.alerts).not_to be_nil
    expect(Noticent.configuration.scopes[:bad]).to be_nil
    expect(Noticent.configuration.alerts.count).to eq(2)
    expect(Noticent.configuration.alerts[:tfa_enabled].name).to eq(:tfa_enabled)
    expect(Noticent.configuration.alerts[:tfa_enabled].scope.name).to eq(:post)
    expect(Noticent.configuration.alerts[:sign_up].tags).to eq(%i[foo bar])
  end

  it 'should force alert uniqueness across scopes' do
    expect do
      Noticent.configure do
        scope :post do
          alert(:a1) {}
        end
        scope :comment do
          alert(:a1) {}
        end
      end
    end.to raise_error(Noticent::BadConfiguration)
  end

  it 'should handle bad notifications' do
    Noticent.configure do
      scope :post do
        alert(:boo) {}
      end
    end
    expect { Noticent.notify('hello', {}) }.to raise_error(Noticent::InvalidAlert)
    payload = build(:post_payload)
    expect { Noticent.notify(:bar, payload) }.to raise_error(Noticent::InvalidAlert)
  end

  it 'should find the right alert' do
    Noticent.configure do
      scope :post do
        alert(:foo) {}
      end
    end

    p1 = build(:post_payload)
    expect { Noticent.notify(:foo, p1) }.not_to raise_error
    expect { Noticent.notify(:bar, p1) }.to raise_error(Noticent::InvalidAlert)
  end

  it 'should dispatch' do
    Noticent.configure do
      channel(:email) {}
      scope :post do
        alert(:new_signup) do
          notify(:users)
        end
      end
    end

    rec = create_list(:recipient, 3)
    p1 = build(:post_payload, _users: rec)
    Noticent.notify(:new_signup, p1)
  end
end
