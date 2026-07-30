PREFIX  ?= $(HOME)/.local
BIN     := $(PREFIX)/bin
AGENTS  := $(HOME)/Library/LaunchAgents
LABEL   := com.caffeinum.alphatab
PLIST   := $(AGENTS)/$(LABEL).plist

SWIFTC  ?= swiftc
SWIFTFLAGS ?= -O

.PHONY: all build install uninstall agent unagent restart clean

all: build

build: bin/alphatab bin/helium-raise

bin/%: src/%.swift
	@mkdir -p bin
	$(SWIFTC) $(SWIFTFLAGS) -o $@ $<

install: build
	@mkdir -p $(BIN)
	install -m 755 bin/alphatab      $(BIN)/alphatab
	install -m 755 bin/helium-raise  $(BIN)/helium-raise
	install -m 755 scripts/skhd-cheatsheet.sh $(BIN)/skhd-cheatsheet
	@echo "installed to $(BIN)"
	@$(MAKE) --no-print-directory agent

# the switcher stays resident so the first keypress is a signal, not a cold
# start — launchd keeps it up and brings it back if it ever dies
agent:
	@mkdir -p $(AGENTS)
	@sed 's|@LABEL@|$(LABEL)|g; s|@BIN@|$(BIN)/alphatab|g' \
		launchd/agent.plist.in > $(PLIST)
	@launchctl bootout gui/$$(id -u)/$(LABEL) 2>/dev/null || true
	@# bootout returns before the service is actually gone, so bootstrapping
	@# straight after it races and fails with EIO — retry until it takes
	@n=0; until launchctl bootstrap gui/$$(id -u) $(PLIST) 2>/dev/null; do \
		n=$$((n+1)); \
		if [ $$n -ge 25 ]; then launchctl bootstrap gui/$$(id -u) $(PLIST); exit 1; fi; \
		/bin/sleep 0.2; \
	done
	@echo "loaded $(LABEL)"

restart:
	@launchctl kickstart -k gui/$$(id -u)/$(LABEL)
	@echo "restarted $(LABEL)"

unagent:
	@launchctl bootout gui/$$(id -u)/$(LABEL) 2>/dev/null || true
	@rm -f $(PLIST)
	@echo "unloaded $(LABEL)"

uninstall: unagent
	rm -f $(BIN)/alphatab $(BIN)/helium-raise $(BIN)/skhd-cheatsheet

clean:
	rm -rf bin
