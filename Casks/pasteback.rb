cask "pasteback" do
  version "0.5.0"
  sha256 "01cac89e4bfa572208644649056bbf6205c4f55710758e5aa8f5831eb8bbf477"

  url "https://github.com/JohnSmitho91p8/Pasteback/releases/download/v#{version}/Pasteback-#{version}-universal.dmg"
  name "Pasteback"
  desc "Local clipboard history with quick paste and C++ previews"
  homepage "https://github.com/JohnSmitho91p8/Pasteback"

  auto_updates true
  depends_on macos: :sonoma

  app "Pasteback.app"
end
