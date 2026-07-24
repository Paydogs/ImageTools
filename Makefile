APP := ImageTools.app
DERIVED := .build/xcode
PRODUCT := $(DERIVED)/Build/Products/Release/$(APP)

.PHONY: compile generate clean run icon

## compile: Generate the Xcode project (Tuist) and build ImageAssetTools.app into this folder (overwrites existing).
compile: generate
	xcodebuild -project ImageTools.xcodeproj -scheme ImageTools \
		-configuration Release -derivedDataPath $(DERIVED) \
		CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO build
	rm -rf $(APP)
	cp -R "$(PRODUCT)" ./

## generate: Regenerate the Xcode project from Project.swift.
generate:
	tuist generate --no-open

## icon: Regenerate the app icon asset catalog from the SF Symbol.
icon:
	swift Scripts/make_appiconset.swift Resources/Assets.xcassets/AppIcon.appiconset

## clean: Remove the built app, generated project, and build artifacts.
clean:
	rm -rf $(APP) $(DERIVED) ImageTools.xcodeproj ImageTools.xcworkspace .build

## run: Build (if needed) and launch the app.
run: compile
	open $(APP)
