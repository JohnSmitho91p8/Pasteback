cask "pasteback" do
  version "0.5.1"
  sha256 "e70c209257df1587e90790873a44936147828d76e392338ae9eb1221f31770f8"

  url "https://github.com/JohnSmitho91p8/Pasteback/releases/download/v#{version}/Pasteback-#{version}-universal.dmg"
  name "Pasteback"
  desc "Local clipboard history with quick paste and C++ previews"
  homepage "https://github.com/JohnSmitho91p8/Pasteback"

  auto_updates true
  depends_on macos: :sonoma

  app "Pasteback.app"
end
