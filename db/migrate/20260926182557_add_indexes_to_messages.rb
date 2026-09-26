# frozen_string_literal: true

class AddIndexesToMessages < ActiveRecord::Migration[8.1]
  def change
    add_index :messages, [:conversation_id, :created_at]
  end
end
