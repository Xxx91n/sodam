cask "sodam" do
  version "0.2.8"
  sha256 "49aa3d1e82d68137ff3beafd047c92596b75b0974fc16c2b6e3bb7bf1bad8fa2"

  url "https://github.com/sodahub-org/sodam/releases/download/v#{version}/sodam-#{version}-macos-aarch64.zip"
  name "SodaM"
  desc "Native Qishui Music desktop client"
  homepage "https://github.com/sodahub-org/sodam"

  depends_on macos: :monterey
  depends_on arch: :arm64

  app "SodaM.app"

  zap trash: "~/Library/Application Support/sodam"
end
