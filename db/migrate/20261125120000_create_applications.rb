class CreateApplications < ActiveRecord::Migration[8.1]
  def change
    create_table :applications, id: :uuid do |t|
      t.string :name, null: false
      t.string :api_key_digest, limit: 64, null: false
      t.timestamps
      t.index :api_key_digest, unique: true
      t.check_constraint "api_key_digest ~ '^[0-9a-f]{64}$'", name: "applications_api_key_digest_format"
    end
  end
end
