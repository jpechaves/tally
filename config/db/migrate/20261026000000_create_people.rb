# frozen_string_literal: true

# The people of the household (issue #21, docs/architecture.md, section 6.1): each account
# belongs to one, and a counterparty can be one of them (the "This is me" mark, now for
# anyone in the household). The first person is you; your accounts and the counterparties
# already marked as you become theirs.
#
# accounts.template is the account's kind among Importers::ACCOUNTS ("Nubank conta"):
# the name it had so far, and the key the importers use, while the name can now carry its
# owner ("Nubank conta (Bruno)").
ROM::SQL.migration do
  up do
    create_table :people, strict: true do
      primary_key :id
      column :name, :text, null: false, unique: true
      column :created_at, :text, null: false, default: Sequel.lit("(strftime('%Y-%m-%dT%H:%M:%fZ', 'now'))")
    end
    self[:people].insert(id: 1, name: "Eu")

    # SQLite can only add a foreign key column that may be null; the app always sets it.
    alter_table(:accounts) do
      add_foreign_key :person_id, :people
      add_column :template, :text
    end
    self[:accounts].update(person_id: 1, template: :name)

    alter_table(:counterparties) { add_foreign_key :person_id, :people }
    self[:counterparties].where(is_self: 1).update(person_id: 1)
  end

  down do
    alter_table(:counterparties) { drop_column :person_id }
    alter_table(:accounts) do
      drop_column :template
      drop_column :person_id
    end
    drop_table :people
  end
end
