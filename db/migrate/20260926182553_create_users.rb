# frozen_string_literal: true

class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string  :email_address,  null: false
      t.string  :password_digest, null: false
      t.integer :token_balance,   null: false, default: 10_000

      t.timestamps
    end

    add_index :users, :email_address, unique: true
    add_check_constraint :users, "token_balance >= 0", name: "token_balance_non_negative"
  end
end
