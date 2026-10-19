# frozen_string_literal: true

module Tally
  module Repos
    # Payees you said are or aren't subscriptions (Tally::Subscriptions).
    class SubscriptionRepo < Tally::DB::Repo
      KINDS = %w[dismissed marked].freeze

      def marks = subscription_marks.dataset.order(Sequel.desc(:id)).all

      def keys(kind) = subscription_marks.dataset.where(kind:).select_map(:key)

      # One mark per payee: a new one replaces the old.
      def mark(key:, kind:, title:)
        subscription_marks.dataset.insert_conflict(target: :key, update: {kind: Sequel[:excluded][:kind], title: Sequel[:excluded][:title]})
          .insert(key:, kind:, title:)
      end

      def unmark(id) = subscription_marks.dataset.where(id:).delete
    end
  end
end
