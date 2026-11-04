cask "macos-webcam-controller" do
  version "1.1.0"
  sha256 "5f0e9f31b0dc8e8c147cf74d474a428ba814f9d0b9487fb681388ff77006fb06"

  url "https://github.com/SilverFeit/MacOS-WebCam-Controller/releases/download/v#{version}/MacOS-WebCam-Controller-#{version}.dmg"
  name "MacOS WebCam Controller"
  desc "Direct USB UVC hardware webcam controller for macOS Menu Bar and CLI (webcamctl)"
  homepage "https://github.com/SilverFeit/MacOS-WebCam-Controller"

  depends_on macos: ">= :sonoma"
  depends_on arch: :arm64

  app "WebCam Controller.app"
  binary "#{appdir}/WebCam Controller.app/Contents/MacOS/webcamctl"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-cr", "#{appdir}/WebCam Controller.app"],
                   sudo: false
  end

  zap trash: [
    "~/Library/Logs/WebCamController.log",
    "~/Library/Preferences/com.webcamcontroller.uvc.plist",
  ]
end
