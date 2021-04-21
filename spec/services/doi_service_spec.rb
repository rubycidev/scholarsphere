# frozen_string_literal: true

require 'rails_helper'
require 'data_cite'

RSpec.describe DoiService do
  subject(:call_service) { described_class.call(resource) }

  let(:client_mock) { instance_spy 'DataCite::Client' }
  let(:work_version_metadata_mock) { instance_spy 'DataCite::Metadata::WorkVersion' }
  let(:collection_metadata_mock) { instance_spy 'DataCite::Metadata::Collection' }

  before do
    allow(DataCite::Client).to receive(:new).and_return(client_mock)
    allow(DataCite::Metadata::WorkVersion).to receive(:new).and_return(work_version_metadata_mock)
    allow(DataCite::Metadata::Collection).to receive(:new).and_return(collection_metadata_mock)
  end

  describe '.call' do
    context 'when given a WorkVersion' do
      let(:resource) { work_version }
      let(:work_version) { FactoryBot.build_stubbed :work_version }

      before do
        allow(resource).to receive(:update_attribute)
        allow(resource).to receive(:valid?).and_return(true)
      end

      context "when the WorkVersion's doi field is empty" do
        before { work_version.doi = nil }

        context 'when the WorkVersion is DRAFT' do
          before { allow(work_version).to receive(:draft?).and_return(true) }

          it 'registers a new doi' do
            call_service
            expect(client_mock).to have_received(:register)
          end

          it 'saves the doi on the WorkVersion db record' do
            allow(client_mock).to receive(:register).and_return(['new/doi', { some: :metadata }])
            call_service
            expect(work_version).to have_received(:update_attribute).with(:doi, 'new/doi')
          end
        end

        context 'when the WorkVersion is PUBLISHED' do
          before do
            allow(work_version).to receive(:draft?).and_return(false)
            allow(work_version).to receive(:published?).and_return(true)
          end

          it 'publishes a new doi with metadata' do
            allow(work_version_metadata_mock).to receive(:attributes).and_return(mocked: :metadata)
            call_service
            expect(DataCite::Metadata::WorkVersion).to have_received(:new).with(
              resource: work_version,
              public_identifier: work_version.uuid
            )
            expect(client_mock).to have_received(:publish).with(
              doi: nil,
              metadata: { mocked: :metadata }
            )
          end

          it 'saves the doi on the WorkVersion db record' do
            allow(client_mock).to receive(:publish).and_return(['new/doi', { some: :metadata }])
            call_service
            expect(work_version).to have_received(:update_attribute).with(:doi, 'new/doi')
          end
        end
      end

      context "when the WorkVersion's doi field is present" do
        before { work_version.doi = 'existing/doi' }

        context 'when the WorkVersion is DRAFT' do
          before { allow(work_version).to receive(:draft?).and_return(true) }

          it 'does nothing' do
            call_service
            expect(client_mock).not_to have_received(:register)
            expect(client_mock).not_to have_received(:publish)
          end
        end

        context 'when the WorkVersion is PUBLISHED' do
          before do
            allow(work_version).to receive(:draft?).and_return(false)
            allow(work_version).to receive(:published?).and_return(true)
          end

          it 'publishes the doi with metadata' do
            allow(work_version_metadata_mock).to receive(:attributes).and_return(mocked: :metadata)
            call_service
            expect(DataCite::Metadata::WorkVersion).to have_received(:new).with(
              resource: work_version,
              public_identifier: work_version.uuid
            )
            expect(client_mock).to have_received(:publish).with(
              doi: 'existing/doi',
              metadata: { mocked: :metadata }
            )
          end

          it 'does not update the WorkVersion db record' do
            call_service
            expect(work_version).not_to have_received(:update_attribute)
          end
        end
      end
    end

    context 'when given a Work' do
      let(:resource) { work }
      let(:work) { FactoryBot.build_stubbed :work }
      let(:latest_work_version) { FactoryBot.build_stubbed :work_version, work: work }

      before do
        allow(work).to receive(:latest_version).and_return(latest_work_version)
        allow(work).to receive(:update_attribute)
        allow(work).to receive(:valid?).and_return(true)
        allow(work).to receive(:update_index)
      end

      context "when the Work's doi field is empty" do
        before { work.doi = nil }

        context "when the work's latest version is a DRAFT version" do
          before { allow(latest_work_version).to receive(:draft?).and_return(true) }

          it 'registers a new doi' do
            call_service
            expect(client_mock).to have_received(:register)
            expect(work).to have_received(:update_index)
          end

          it 'saves the doi on the Work db record' do
            allow(client_mock).to receive(:register).and_return(['new/doi', { some: :metadata }])
            call_service
            expect(work).to have_received(:update_attribute).with(:doi, 'new/doi')
            expect(work).to have_received(:update_index)
          end
        end

        context "when the work's latest version is a PUBLISHED verison" do
          before do
            allow(latest_work_version).to receive(:draft?).and_return(false)
            allow(latest_work_version).to receive(:published?).and_return(true)
          end

          it 'publishes a new doi with metadata' do
            allow(work_version_metadata_mock).to receive(:attributes).and_return(mocked: :metadata)
            call_service
            expect(DataCite::Metadata::WorkVersion).to have_received(:new).with(
              resource: latest_work_version,
              public_identifier: work.uuid
            )
            expect(client_mock).to have_received(:publish).with(
              doi: nil,
              metadata: { mocked: :metadata }
            )
            expect(work).to have_received(:update_index)
          end

          it 'saves the doi on the Work db record' do
            allow(client_mock).to receive(:publish).and_return(['new/doi', { some: :metadata }])
            call_service
            expect(work).to have_received(:update_attribute).with(:doi, 'new/doi')
            expect(work).to have_received(:update_index)
          end
        end
      end

      context "when the Work's doi field is present" do
        before { work.doi = 'existing/doi' }

        context "when the work's latest version is a DRAFT version" do
          before { allow(latest_work_version).to receive(:draft?).and_return(true) }

          it 'does nothing' do
            call_service
            expect(client_mock).not_to have_received(:register)
            expect(client_mock).not_to have_received(:publish)
            expect(work).not_to have_received(:update_index)
          end
        end

        context "when the work's latest version is a PUBLISHED verison" do
          before do
            allow(latest_work_version).to receive(:draft?).and_return(false)
            allow(latest_work_version).to receive(:published?).and_return(true)
          end

          it 'publishes the doi with metadata' do
            allow(work_version_metadata_mock).to receive(:attributes).and_return(mocked: :metadata)
            call_service
            expect(DataCite::Metadata::WorkVersion).to have_received(:new).with(
              resource: latest_work_version,
              public_identifier: work.uuid
            )
            expect(client_mock).to have_received(:publish).with(
              doi: 'existing/doi',
              metadata: { mocked: :metadata }
            )
          end

          it 'does not update the Work db record' do
            call_service
            expect(work).not_to have_received(:update_attribute)
            expect(work).not_to have_received(:update_index)
          end
        end
      end
    end

    context 'when given a Collection' do
      let(:resource) { collection }
      let(:collection) { FactoryBot.build_stubbed :collection }

      before do
        allow(collection).to receive(:valid?).and_return(true)
        allow(collection).to receive(:update_attribute)
      end

      context "when the Collection's doi field is empty" do
        before { collection.doi = nil }

        it 'publishes a new doi with metadata' do
          allow(collection_metadata_mock).to receive(:attributes).and_return(mocked: :metadata)
          call_service
          expect(DataCite::Metadata::Collection).to have_received(:new).with(
            resource: collection,
            public_identifier: collection.uuid
          )
          expect(client_mock).to have_received(:publish).with(
            doi: nil,
            metadata: { mocked: :metadata }
          )
        end

        it 'saves the doi on the Collection db record' do
          allow(client_mock).to receive(:publish).and_return(['new/doi', { some: :metadata }])
          call_service
          expect(collection).to have_received(:update_attribute).with(:doi, 'new/doi')
        end
      end

      context "when the Collection's doi field is present" do
        before { collection.doi = 'existing/doi' }

        it 'publishes the doi with metadata' do
          allow(collection_metadata_mock).to receive(:attributes).and_return(mocked: :metadata)
          call_service
          expect(DataCite::Metadata::Collection).to have_received(:new).with(
            resource: collection,
            public_identifier: collection.uuid
          )
          expect(client_mock).to have_received(:publish).with(
            doi: 'existing/doi',
            metadata: { mocked: :metadata }
          )
        end

        it 'does not update the Collection db record' do
          call_service
          expect(collection).not_to have_received(:update_attribute)
        end
      end
    end

    context 'when given some other type of object' do
      let(:resource) { FactoryBot.build_stubbed :user }

      it { expect { call_service }.to raise_error(ArgumentError) }
    end

    context 'when given an invalid resource' do
      let(:work) { FactoryBot.create(:work, has_draft: false, versions_count: 1) }
      let(:version) { work.versions.first }

      before do
        allow(client_mock).to receive(:publish).and_return(['new/doi', { some: :metadata }])

        version.update_attribute(:description, nil)
      end

      context 'when given an invalid WorkVersion' do
        let(:resource) { version }

        it 'still saves the DOI' do
          # Sanity check
          expect(version).not_to be_valid

          expect {
            call_service
          }.to change {
            resource.reload.doi
          }.from(nil).to('new/doi')
        end
      end

      context 'when given a Work with an invalid version' do
        let(:resource) { work }

        it 'still saves the DOI' do
          # Sanity check
          expect(version).not_to be_valid

          expect {
            call_service
          }.to change {
            resource.reload.doi
          }.from(nil).to('new/doi')
        end
      end

      context 'when given a Collection' do
        let(:resource) { create :collection }

        before { resource.update_attribute(:description, nil) }

        it 'still saves the DOI' do
          # Sanity check
          expect(resource).not_to be_valid

          expect {
            call_service
          }.to change {
            resource.reload.doi
          }.from(nil).to('new/doi')
        end
      end
    end

    context 'when the metadata mapper cannot build valid metadata' do
      let(:resource) { FactoryBot.create :work_version, doi: nil }

      before do
        allow(resource).to receive(:draft?).and_return(false)
        allow(work_version_metadata_mock).to receive(:validate!).and_raise(DataCite::Metadata::ValidationError)
      end

      it do
        expect {
          call_service
        }.to raise_error(DataCite::Metadata::ValidationError)
      end
    end

    context 'when the doi client raises an error' do
      let(:resource) { FactoryBot.create :work_version, doi: nil }

      before do
        allow(resource).to receive(:draft?).and_return(true)
        allow(client_mock).to receive(:register).and_raise(DataCite::Client::Error)
      end

      it do
        expect {
          call_service
        }.to raise_error(DataCite::Client::Error)
      end
    end
  end
end
