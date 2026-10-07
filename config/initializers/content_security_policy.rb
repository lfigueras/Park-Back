# Be sure to restart your server when you modify this file.

# Define an application-wide content security policy.
# See the Securing Rails Applications Guide for more information:
# https://guides.rubyonrails.org/security.html#content-security-policy-header

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.base_uri :self
    policy.object_src :none
    policy.frame_ancestors :none
    policy.form_action :self
    policy.font_src :self
    policy.img_src :self, :data, :blob, "https://tile.openstreetmap.org", "https://unpkg.com",
      "https://*.google-analytics.com", "https://www.googletagmanager.com"
    policy.script_src :self, "https://unpkg.com", "https://www.googletagmanager.com"
    policy.style_src :self, :unsafe_inline, "https://unpkg.com"
    policy.connect_src :self, "https://*.google-analytics.com", "https://*.analytics.google.com",
      "https://www.googletagmanager.com"
  end

  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(32) }
  config.content_security_policy_nonce_directives = %w[script-src]
  config.content_security_policy_nonce_auto = true
end
