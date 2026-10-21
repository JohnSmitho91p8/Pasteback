cask "pasteback" do
  version "0.6.0"
  sha256 "398ed3f0c568393df671ac752aa2fa60718f9b4a9baa43d2bfcbed843da79e29"

  url "https://github.com/JohnSmitho91p8/Pasteback/releases/download/v#{version}/Pasteback-#{version}-universal.dmg"
  name "Pasteback"
  desc "Local clipboard history with quick paste and C++ previews"
  homepage "https://github.com/JohnSmitho91p8/Pasteback"

  auto_updates true
  depends_on macos: :sonoma

  app "Pasteback.app"
end
