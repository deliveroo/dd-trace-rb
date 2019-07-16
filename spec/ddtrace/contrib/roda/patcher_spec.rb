require 'spec_helper'
require 'ddtrace'
require 'ddtrace/contrib/analytics_examples'
require 'rack/test'
require 'roda'

RSpec.describe 'Roda instrumentation' do
	include Rack::Test::Methods

	let(:tracer) { get_test_tracer }
	let(:configuration_options) { { tracer: tracer } }
	let(:spans) { tracer.writer.spans }
	let(:span) { spans.first }

	before(:each) do
		Datadog.configure do |c|
			c.use :roda, configuration_options
		end
	end

	around do |example|
		Datadog.registry[:roda].reset_configuration!
		example.run
		Datadog.registry[:roda].reset_configuration!
	end

	shared_context 'basic roda app' do
		let(:app) do
			Class.new(Roda) do
				plugin :all_verbs
				route do |r|
					r.root do
						# GET /
						r.get do
							"Hello World!"
						end
					end
					r.is 'worlds', Integer do |world|
						r.put do
							"UPDATE"
						end
						# GET /worlds/1
						r.get do
							"Hello, world #{r.params['world']}"
						end
					end
				end
			end
		end
	end

	shared_context 'Roda app with server error' do
		let(:app) do
			Class.new(Roda) do
				route do |r|
					r.root do
						r.get do
							r.halt([500, {'Content-Type'=>'text/html'}, ['test']])
						end
					end
				end
			end
		end
	end

	context 'when configured' do
		context 'with default settings' do
			context 'and a successful request is made' do

				include_context 'basic roda app'
				subject(:response) { get '/' }

				context 'for a basic GET endpoint' do 
					it do
						expect(response.status).to eq(200)
						expect(response.header).to eq({"Content-Type"=>"text/html", "Content-Length"=>"12"})
						expect(spans).to have(1).items
						# expect(span.get_metric(Datadog::Ext::Analytics::TAG_SAMPLE_RATE)).to eq(nil)
						# expect(span.span_type).to eq(Datadog::Ext::HTTP::TYPE_INBOUND)
						# expect(span.status).to eq(0)
						# expect(span.resource).to eq("GET")
						expect(span.name).to eq("roda.request")
						# expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq('GET')
						# expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq('/')
						# expect(span.parent).to be nil
					end

					it_behaves_like 'analytics for integration', ignore_global_flag: false do
						before { is_expected.to be_ok }
						let(:analytics_enabled_var) { Datadog::Contrib::Roda::Ext::ENV_ANALYTICS_ENABLED }
	          let(:analytics_sample_rate_var) { Datadog::Contrib::Roda::Ext::ENV_ANALYTICS_SAMPLE_RATE }
					end
				end

				context 'for a GET endpoint with an id' do 

					subject(:params_response) { get 'worlds/1' }

					it do
						expect(params_response.status).to eq(200)
						expect(params_response.header).to eq({"Content-Type"=>"text/html", "Content-Length"=>"13"})
						
						expect(spans).to have(1).items
						expect(span.span_type).to eq(Datadog::Ext::HTTP::TYPE_INBOUND)
						expect(span.get_metric(Datadog::Ext::Analytics::TAG_SAMPLE_RATE)).to eq(nil)
						expect(span.status).to eq(0)
						expect(span.name).to eq("roda.request")
						expect(span.resource).to eq("GET")
						expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq('GET')
						expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq('/worlds/1')
						expect(span.parent).to be nil
					end
				end					
			end

			context 'and an error occurs' do
				context 'with a 404' do
					include_context 'basic roda app'
					subject(:response) { get '/unsuccessful_endpoint' }
					it do
						expect(response.status).to eq(404)
						expect(response.header).to eq({"Content-Type"=>"text/html", "Content-Length"=>"0"})
						expect(spans).to have(1).items
						expect(span.name).to eq("roda.request")
					end
				end

				context 'with a 500' do
					include_context 'Roda app with server error'
					subject(:response) {get '/'}
					it do
						expect(response.status).to eq(500)
						expect(response.header).to eq({"Content-Type"=>"text/html", "Content-Length"=>"4"})
					 
						expect(spans).to have(1).items
						# expect(span.parent).to be nil
						# expect(span.get_metric(Datadog::Ext::Analytics::TAG_SAMPLE_RATE)).to eq(nil)
						# expect(span.span_type).to eq(Datadog::Ext::HTTP::TYPE_INBOUND)
						# expect(span.resource).to eq("GET")
						expect(span.name).to eq("roda.request")
						# expect(span.status).to eq(1)
						# expect(span.get_tag(Datadog::Ext::HTTP::METHOD)).to eq('GET')
						# expect(span.get_tag(Datadog::Ext::HTTP::URL)).to eq('/')
					end
				end	
			end

			context 'when the tracer is disabled' do  
				include_context 'basic roda app'
				subject(:response) {get '/'}

				let(:tracer) { get_test_tracer(enabled: false) }

				it do
					is_expected.to be_ok
					expect(spans).to be_empty
				end
			end

		end
	end
end