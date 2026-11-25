class Application < ApplicationRecord
  self.filter_attributes += [ :api_key_digest ]
  attr_readonly :api_key_digest

  validates :name, presence: true
  validates :api_key_digest, format: { with: ApplicationApiKey::TOKEN_PATTERN }

  def self.issue_key!(name:)
    key = ApplicationApiKey.generate
    application = create!(name: name, api_key_digest: ApplicationApiKey.digest(key))
    [ application, key ]
  end

  def self.authenticate_bearer(authorization)
    key = ApplicationApiKey.from_authorization(authorization)
    return unless key

    find_by(api_key_digest: ApplicationApiKey.digest(key))
  end
end
