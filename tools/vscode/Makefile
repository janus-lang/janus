.PHONY: all install package clean

all: package

install:
	npm install

package: compile
	yes | npx vsce package --out ../../zig-out/janus-lang-0.2.0.vsix

compile: install
	npm run compile

clean:
	rm -rf out node_modules *.vsix

install-all: package
	./install-extension.sh
