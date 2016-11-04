require 'minitest'
require 'minitest/autorun'

require 'ddtrace/encoding'
require 'ddtrace/transport'
require 'ddtrace/tracer'
require 'ddtrace/buffer'
require 'ddtrace/span'

# Return a test tracer instance with a faux writer.
def get_test_tracer
  Datadog::Tracer.new(writer: FauxWriter.new)
end

def get_adapter_name
  adapter_name = ::ActiveRecord::Base.connection_config[:adapter]
  Datadog::Contrib::Rails::Utils.normalize_vendor(adapter_name)
end

# FauxWriter is a dummy writer that buffers spans locally.
class FauxWriter < Datadog::Writer
  def initialize
    super(transport: FauxTransport.new(HOSTNAME, PORT))

    # easy access to registered components
    @spans = []
    @services = {}
  end

  def write(trace, services)
    super(trace, services)
    @spans << trace
    @services = services
  end

  def spans
    spans = @spans
    @spans = []
    spans.flatten
  end
end

# FauxTransport is a dummy HTTPTransport that doesn't send data to an agent.
class FauxTransport < Datadog::HTTPTransport
  def send(*)
    # noop
  end
end

# update Datadog user configuration; you should pass:
#
# * +key+: the key that should be updated
# * +value+: the value of the key
def update_config(key, value)
  ::Rails.configuration.datadog_trace[key] = value
  config = { config: ::Rails.application.config }
  Datadog::Contrib::Rails::Framework.configure(config)
end

# reset default configuration and replace any dummy tracer
# with the global one
def reset_config
  ::Rails.configuration.datadog_trace = {}
  Datadog::Contrib::Rails::Framework.configure({})
end
