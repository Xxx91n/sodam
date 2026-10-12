cask "sodam" do
  version "0.2.3"
  sha256 "f564bcdff70a778bb1de7c06d6d3bf317ca0738d9e8e80fa0e7290688b8c91e6"

  url "https://github.com/sodahub-org/sodam/releases/download/v#{version}/sodam-#{version}-macos-aarch64.zip"
  name "SodaM"
  desc "Native Qishui Music desktop client"
  homepage "https://github.com/sodahub-org/sodam"

  depends_on macos: :monterey
  depends_on arch: :arm64

  app "SodaM.app"

  zap trash: "~/Library/Application Support/sodam"
end
