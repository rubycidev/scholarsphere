# frozen_string_literal: true

require 'rails_helper'

describe MergeCollection do
  subject(:merge_result) { described_class.call(collection.uuid, force: force_merge) }

  let(:force_merge) { false }
  let(:collection) { create(:collection, :with_a_doi, works: [work1, work2]) }
  let(:user) { create(:user) }
  let(:actor) { user.actor }

  let(:work1) { create(:work, has_draft: false, depositor: actor) }
  let(:work2) { create(:work, has_draft: false, depositor: actor) }
  let(:common_metadata) { attributes_for(:work_version, :published, :with_complete_metadata) }

  # Update both works to have identical metadata on their versions, so we can induce various error states easily
  before do
    collection.update(keyword: common_metadata[:keyword])
    work1.versions.first.update(common_metadata)
    work2.versions.first.update(common_metadata)

    work1.versions.first.update(title: 'work1.png')
    work2.versions.first.update(title: 'work2.png')

    collection.creators = work1.versions.first.creators.map(&:dup)
    work2.versions.first.creators = work1.versions.first.creators.map(&:dup)
    collection.save!
    work2.save!
  end

  context 'when the works in the collection are inelegible to be merged' do
    context 'when a work has too many versions' do
      let(:work1) { create(:work, versions_count: 1, has_draft: false) }
      let(:work2) { create(:work, versions_count: 2, has_draft: false) }

      it 'returns an error message' do
        error_msg = "Work-#{work2.id} has 2 work versions, but must only have 1"
        expect(merge_result.errors).to include(a_string_matching(error_msg))
      end
    end

    context 'when a work has too many files' do
      let (:work1) { create(:work, versions: [v1], depositor: actor) }
      let (:work2) { create(:work, has_draft: false, depositor: actor) }
      let (:v1) { create(:work_version, :with_files, :published, file_count: 2) }

      it 'returns an error message' do
        expect(merge_result.errors).to include("Work-#{work1.id} has 2 files, but must only have 1")
      end
    end

    context 'when the works in the collection have mismatched work-level metadata' do
      let(:work1) { create(:work, has_draft: false) }
      let(:work2) { create(:work, has_draft: false) }

      xit 'returns an error message' do
        error_msg = /Work-#{work1.id} has different work metadata than Work-#{work2.id}/i
        expect(merge_result.errors).to include(a_string_matching(error_msg))
      end
    end

    context 'when the resulting work has an ActiveRecord validation error' do
      before do
        collection # create collection in db

        # Force work1 to be invalid
        work1.work_type = nil
        work1.save(validate: false)
        work2.work_type = nil
        work2.save(validate: false)
      end

      it 'adds any ActiveRecord validation errors on the new work to the errors array' do
        expect(merge_result.errors).to include(a_string_matching(/work type can't be blank/i))
      end
    end

    context 'when the works in the collection have mismatched version-level metadata' do
      before do
        work1.versions.first.update(description: 'new description')
      end

      context 'when the force param is false' do
        it 'returns an error message' do
          error_msg = /Work-#{work1.id} has different WorkVersion metadata than Work-#{work2.id}/i
          expect(merge_result.errors).to include(a_string_matching(error_msg))
          expect(merge_result.errors).to include(a_string_matching(/new description/i))
        end
      end

      context 'when the force param is true' do
        let(:force_merge) { true }

        it 'does not return an error message' do
          expect(merge_result).to be_successful
          expect(merge_result.errors.length).to eq 0
        end
      end
    end

    context 'when a work in the collection is not published' do
      before do
        work1.versions.first.update(aasm_state: 'draft')
      end

      it 'returns an error message' do
        expect(merge_result.errors).to include("Work-#{work1.id} is not published")
      end
    end

    context 'when the works in the collection have mismatched access controls' do
      let(:edit_user) { create(:user) }
      let(:work1) { create(:work, has_draft: false, depositor: actor, edit_users: [edit_user]) }
      let(:work2) { create(:work, has_draft: false, depositor: actor) }

      it 'returns an error message' do
        error_msg = /Work-#{work1.id} has different discover users than Work-#{work2.id}/i
        expect(merge_result.errors).to include(a_string_matching(error_msg))
      end
    end

    context 'when the works in the collection have mismatched creators' do
      before do
        work2.versions.first.creators = build_list(:authorship, 1)
        work2.save!
      end

      context 'when the force param is false' do
        it 'returns an error message' do
          error_msg = /Collection-#{collection.id} has different creators than Work-#{work2.id}/i
          expect(merge_result.errors).to include(a_string_matching(error_msg))
        end
      end

      context 'when the force param is true' do
        let(:force_merge) { true }

        it 'does not return an error message' do
          expect(merge_result).to be_successful
          expect(merge_result.errors.length).to eq 0
        end
      end
    end
  end

  context 'when the works in the collection have mismatched keywords' do
    before do
      work2.versions.first.update(keyword: 'new keyword')
    end

    context 'when the force param is false' do
      it 'returns an error message' do
        error_msg = /Collection-#{collection.id} has different keywords than Work-#{work2.id}/i
        expect(merge_result.errors).to include(a_string_matching(error_msg))
      end
    end

    context 'when the force param is true' do
      let(:force_merge) { true }

      it 'does not return an error message' do
        expect(merge_result).to be_successful
        expect(merge_result.errors.length).to eq 0
      end
    end
  end

  context 'when the database transaction fails' do
    before do
      allow(WorkIndexer).to receive(:call).and_raise(StandardError)
    end

    it 'rolls back all changes' do
      expect {
        begin
          merge_result
        rescue StandardError
          # noop
        end
      }.not_to change(Work, :count)

      expect(collection.reload).to be_present
    end
  end

  context 'when the works in the collection are eligible to be merged' do
    it 'merges the works into a single work' do
      expect(merge_result).to be_successful

      new_work = Work.last
      expect(new_work.versions.length).to eq 1

      version = new_work.versions.first

      # spot check attributes
      expect(new_work.doi).to be_nil
      expect(version).not_to be_published
      expect(version.title).to eq collection.title
      expect(version.description).to eq collection[:description]
      expect(version.rights).to eq common_metadata[:rights]
      expect(version.published_date).to eq common_metadata[:published_date]

      # check files
      original_files = [
        work1.versions.first.file_resources,
        work2.versions.first.file_resources
      ].flatten
      expect(version.file_resources).to match_array(original_files)

      # check file names
      new_file_names = [
        'work1.png',
        'work2.png'
      ]
      expect(version.file_version_memberships.map(&:title)).to match_array(new_file_names)

      # check creators
      expect(version.creators.map(&:display_name)).to match_array(work1.versions.first.creators.map(&:display_name))
    end
  end
end
