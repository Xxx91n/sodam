cask "sodam" do
  version "0.3.4"
  sha256 "461749d384e1720354aa561543b1f6fe255b402ea2c8e7d54673ed5e740bbdb6"

  url "https://github.com/sodahub-org/sodam/releases/download/v#{version}/sodam-#{version}-macos-aarch64.zip"
  name "SodaM"
  desc "Native Qishui Music desktop client"
  homepage "https://github.com/sodahub-org/sodam"

  depends_on macos: :monterey
  depends_on arch: :arm64

  app "SodaM.app"

  zap trash: "~/Library/Application Support/sodam"
end
