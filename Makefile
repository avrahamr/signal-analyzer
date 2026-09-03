PROJECT := WiFiSignal.xcodeproj
SCHEME  := WiFiSignal
DERIVED := build
APP     := $(DERIVED)/Build/Products/Debug/WiFiSignal.app

.PHONY: gen open build run test clean

gen:
	xcodegen generate

open: gen
	open $(PROJECT)

build: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -derivedDataPath $(DERIVED) build

run: build
	open $(APP)

test: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -derivedDataPath $(DERIVED) test

clean:
	rm -rf $(DERIVED) $(PROJECT)
