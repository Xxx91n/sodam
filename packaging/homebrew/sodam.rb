cask "sodam" do
  version "0.2.4"
  sha256 "96bf430d6ed08d2f051a0f9cc43afa8ad596e074c8aabb9aad07a34e2edcf752"

  url "https://github.com/sodahub-org/sodam/releases/download/v#{version}/sodam-#{version}-macos-aarch64.zip"
  name "SodaM"
  desc "Native Qishui Music desktop client"
  homepage "https://github.com/sodahub-org/sodam"

  depends_on macos: :monterey
  depends_on arch: :arm64

  app "SodaM.app"

  zap trash: "~/Library/Application Support/sodam"
end
