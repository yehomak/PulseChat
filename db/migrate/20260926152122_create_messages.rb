# frozen_string_literal: true

class CreateMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :messages do |t|
      t.references :conversation, null: false, foreign_key: true
      t.integer :role,        null: false, default: 0
      t.integer :status,      null: false, default: 0
      t.text    :content,     null: false
      t.integer :tokens_used, null: false, default: 0

      t.timestamps
    end
  end
end
