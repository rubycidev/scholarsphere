# frozen_string_literal: true

module Dashboard
  module Form
    class PublishController < BaseController
      def edit
        @resource = WorkVersion
          .includes(file_version_memberships: [:file_resource])
          .find(params[:id])
        authorize(@resource)
        prevalidate
      end

      def update
        @resource = WorkVersion.find(params[:id])
        authorize(@resource)

        @resource.attributes = work_version_params
        # If the user clicks the "Publish" button, *and* there are validation
        # errors, we still want to persist any changes to the draft version's
        # db record, while at the same time showing the publish validation errors
        #
        # The easiest way to do this is to immediately save all the form changes
        # against the draft validations, then mark the record as published and
        # save again--this time using the published validations. That way the
        # appropriate error messages will appear on the form when it's re-rendered
        if publish?
          # WorkVersion#set_thumbnail_selection may be unreliable if the Shrine::ThumbnailJob is delayed
          @resource.set_thumbnail_selection
          @resource.indexing_source = Proc.new { nil }
          @resource.save
          @resource.publish
        end

        validation_context = current_user.admin? ? nil : :user_publish
        process_response(on_error: :edit, validation_context: validation_context)
      end

      private

        # @note Validate the work like we're going to publish it, so we can inform the user ahead of time before they
        # actually attempt it. However, we want to be nice and not yell at them for something they _haven't_ seen yet
        # like rights.
        def prevalidate
          temporarily_publish @resource do
            @resource.validate
            @resource.errors.delete(:rights)
          end
        end

        # Temporarily mark a resource as published (do not save to the
        # database), allow some actions to be performed in a block, then reset
        # the aasm state back to whatever it was previously.
        def temporarily_publish(resource)
          initial_state = resource.aasm_state
          resource.publish unless resource.published?

          yield
        ensure
          resource.aasm_state = initial_state
        end

        # This controller can be used in two ways, either by a user to publish
        # a new WorkVersion (most common scenario), or by an admin to edit an
        # already published version. When we render the form (and re-render the
        # form with errors) we need to know which action the user is
        # attempting, so we can render the proper buttons.
        helper_method :form_should_publish?
        def form_should_publish?
          not_published = !@resource.published?
          marked_as_published_but_not_persisted = (
            @resource.aasm.from_state != :published &&
              @resource.aasm.to_state == :published
          )

          not_published || marked_as_published_but_not_persisted
        end

        def work_version_params
          params
            .require(:work_version)
            .permit(
              :title,
              :description,
              :publisher_statement,
              :subtitle,
              :rights,
              :version_name,
              :published_date,
              :depositor_agreement,
              keyword: [],
              contributor: [],
              publisher: [],
              subject: [],
              language: [],
              identifier: [],
              based_near: [],
              related_url: [],
              source: [],
              creators_attributes: [
                :id,
                :actor_id,
                :_destroy,
                :display_name,
                actor_attributes: [
                  :id,
                  :email,
                  :given_name,
                  :surname,
                  :psu_id
                ]
              ],
              work_attributes: [
                :id,
                :work_type,
                :visibility
              ]
            )
        end
    end
  end
end
