# frozen_string_literal: true

require Rails.root.join('spec', 'support', 'file_helpers')

FactoryBot.define do
  factory :file_resource do
    # Fast version with no image processing.
    # The sequence is used to provide a unique filename to each file, thereby
    # avoiding tripping the validation that each file in a WorkVersion must have
    # a unique filename
    sequence(:file_data) { |n| FileHelpers.image_data "image-#{n}.png" }

    trait :pdf do
      file_data { |n| FileHelpers.pdf_data "pdf-#{n}.pdf" }
    end

    trait :doc do
      file_data { |n| FileHelpers.doc_data "doc-#{n}.docx" }
    end

    # Slow version with full image processing
    trait :with_processed_image do
      file_data { nil }
      file { Rack::Test::UploadedFile.new(FileHelpers.fixture_file('image.png'), 'image/png') }
    end
  end
end
