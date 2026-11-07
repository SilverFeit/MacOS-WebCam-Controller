cask "macos-webcam-controller" do
  version "1.2.0"
  sha256 "67437a3820f5c7bf742356a455c5fd4c3cb6b08e9e52cc5d52985ddd06e97353"

  url "https://github.com/SilverFeit/MacOS-WebCam-Controller/releases/download/v#{version}/MacOS-WebCam-Controller-#{version}.dmg"
  name "MacOS WebCam Controller"
  desc "Direct USB UVC hardware webcam controller for macOS Menu Bar and CLI (webcamctl)"
  homepage "https://github.com/SilverFeit/MacOS-WebCam-Controller"

  depends_on macos: :sonoma
  depends_on arch: :arm64

  app "WebCam Controller.app"
  binary "#{appdir}/WebCam Controller.app/Contents/MacOS/webcamctl"

  if respond_to?(:postflight_steps)
    postflight_steps do
      run "/usr/bin/xattr",
          args: ["-cr", "{{appdir}}/WebCam Controller.app"],
          writable_paths: ["WebCam Controller.app"],
          writable_base: :appdir
    end
  else
    postflight do
      system_command "/usr/bin/xattr",
                     args: ["-cr", "#{appdir}/WebCam Controller.app"],
                     sudo: false
    end
  end

  zap trash: [
    "~/Library/Logs/WebCamController.log",
    "~/Library/Preferences/com.webcamcontroller.uvc.plist",
  ]
end
