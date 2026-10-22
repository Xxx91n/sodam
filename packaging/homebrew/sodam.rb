cask "sodam" do
  version "0.3.5"
  # 发版产物生成后由 packaging/homebrew/sync-tap.sh 自动填入。
  sha256 :no_check

  url "https://github.com/sodahub-org/sodam/releases/download/v#{version}/sodam-#{version}-macos-aarch64.zip"
  name "SodaM"
  desc "Native Qishui Music desktop client"
  homepage "https://github.com/sodahub-org/sodam"

  depends_on macos: :monterey
  depends_on arch: :arm64

  app "SodaM.app"

  zap trash: "~/Library/Application Support/sodam"
end
