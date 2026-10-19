cask "sodam" do
  version "0.3.0"
  sha256 "24482a62dc2d9cd414fdbc4bd3412b67896f45c100b6f70faa5cfdc4dac3a061"

  url "https://github.com/sodahub-org/sodam/releases/download/v#{version}/sodam-#{version}-macos-aarch64.zip"
  name "SodaM"
  desc "Native Qishui Music desktop client"
  homepage "https://github.com/sodahub-org/sodam"

  depends_on macos: :monterey
  depends_on arch: :arm64

  app "SodaM.app"

  zap trash: "~/Library/Application Support/sodam"
end
