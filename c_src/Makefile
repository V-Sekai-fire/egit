CMAKE ?= cmake

# The build is described once, in CMakeLists.txt. rebar3's pre_hook runs this.
# Paths stay relative to this directory: $(abspath) rewrites /c/eg as C:/c/eg
# under MSYS.
all:
	$(CMAKE) -P ../build.cmake

clean:
	rm -rf ../build ../priv/git.so ../priv/git.dll

info:
	@echo "CMAKE=$(CMAKE)"
	@$(CMAKE) --version

.PHONY: all clean info
