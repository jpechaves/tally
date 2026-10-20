# frozen_string_literal: true

module Tally
  module Repos
    # The people of the household (issue #21). The first one is you: your accounts keep
    # their plain names ("Nubank conta"), and everyone else's carry their name
    # ("Nubank conta (Bruno)").
    class PersonRepo < Tally::DB::Repo
      # Your name until you change it on the accounts page.
      FIRST_NAME = "Eu"

      def all = people.order(:id).to_a.then { _1.empty? ? [first] : _1 }

      # You, created the first time.
      def first
        people.order(:id).limit(1).one || begin
          people.dataset.insert(name: FIRST_NAME)
          people.order(:id).limit(1).one
        end
      end

      def find(id) = people.by_pk(id).one

      # More than one person: pages offer a switch between them.
      def household? = people.dataset.count > 1

      # @return [ROM::Struct, nil] the new person, or nil for a blank name or one taken
      def create(name)
        name = name.to_s.strip
        first # you come first, even when someone is added before anything else
        return if name.empty? || people.where(name:).one

        find(people.dataset.insert(name:))
      end

      # Renames a person and the accounts named after them.
      # @return [Boolean] false for a blank name or one taken
      def rename(id, name)
        name = name.to_s.strip
        return false if name.empty? || people.dataset.where(name:).exclude(id:).any?

        transaction do
          people.dataset.where(id:).update(name:)
          unless id == first.id
            accounts.dataset.where(person_id: id).update(name: Sequel.join([:template, " (#{name})"]), updated_at: Repos.now)
          end
        end
        true
      end

      # What an account of this person is called: the importers' name for yours, with the
      # owner's name for anyone else's.
      def account_name(template, person_id) = (person_id == first.id) ? template : "#{template} (#{find(person_id).name})"
    end
  end
end
