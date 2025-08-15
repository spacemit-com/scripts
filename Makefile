# Enhanced Makefile with Docker support for Bianbu Linux Development

PROJECT_DIR      := $(shell pwd)
CONFIG_DIRECTORY := $(PROJECT_DIR)/buildroot-ext/configs
BUILDROOT_EXT    := $(PROJECT_DIR)/buildroot-ext
DL_DIR           ?= $(PROJECT_DIR)/buildroot/dl
OUTPUT_DIR       ?= $(PROJECT_DIR)/output
CCACHE_DIR       ?= $(PROJECT_DIR)/buildroot-ccache
DOCKER_OPTS      ?=
MAKE_JLEVEL      ?= $(shell nproc)
BATCH_MODE       ?=
PARALLEL_BUILD   ?= 1
DIRECT_BUILD     ?=


# Use tput to detect color support
HAS_COLOR := $(shell \
	if [ "$$TERM" != "dumb" ] && [ -n "$$TERM" ] && command -v tput >/dev/null 2>&1; then \
		if tput colors >/dev/null 2>&1 && [ "$$(tput colors 2>/dev/null)" -ge 8 ]; then \
			echo "yes"; \
		else \
			echo "no"; \
		fi; \
	else \
		echo "no"; \
	fi)

ifeq ($(HAS_COLOR),yes)
OK_COLOR := \033[32;01m
NO_COLOR := \033[0m
ERROR_COLOR := \033[31;01m
WARN_COLOR := \033[33;01m
CHECK_OK := ✓
CHECK_FAIL := ✗
else
OK_COLOR :=
NO_COLOR :=
ERROR_COLOR :=
WARN_COLOR :=
CHECK_OK := [OK]
CHECK_FAIL := [FAIL]
endif

# Available configs
TARGETS := $(sort $(shell find $(CONFIG_DIRECTORY) -name 'spacemit_*_defconfig' | sed -n 's/.*\/spacemit_\(.*\)_defconfig/\1/p'))
CONFIGS := $(wildcard $(CONFIG_DIRECTORY)/*)
NUM_CONFIGS := $(words $(CONFIGS))
CONFIG_NAMES := $(foreach config,$(CONFIGS),$(basename $(notdir $(config))))
# Current active config
CONFIG_NAME := $(shell grep "^CONFIG_NAME=" env.mk 2>/dev/null | cut -d'=' -f2)

UID := $(shell id -u)
GID := $(shell id -g)
OS := $(shell uname)


ifdef PARALLEL_BUILD
	# Dynamically calculate parallelism: priority order - command line args, config file, system cores
	MAKE_OPTS += -j$(shell \
		cmdline_jobs=$$(echo "$(MAKEFLAGS)" | sed -n 's/.*-j\([0-9]\+\).*/\1/p'); \
		if [ -n "$$cmdline_jobs" ]; then \
			echo "$$cmdline_jobs"; \
		elif [ -n "$(MAKE_JLEVEL)" ]; then \
			echo "$(MAKE_JLEVEL)"; \
		else \
			nproc; \
		fi)
endif

# Define build command based on whether we are building direct or inside a docker container
ifdef DIRECT_BUILD
define MAKE_BUILDROOT_BUILD
	make -C output/$* $(MAKE_OPTS)
endef

define MAKE_BUILDROOT
	make $(MAKE_OPTS) O=$(OUTPUT_DIR)/$* \
		BR2_EXTERNAL=$(PROJECT_DIR)/buildroot-ext \
		BR2_DL_DIR=$(DL_DIR) \
		BR2_CCACHE_DIR=$(CCACHE_DIR) \
		-C $(PROJECT_DIR)/buildroot
endef

# Parameterized version of MAKE_BUILDROOT macro
define MAKE_BUILDROOT_WITH_TARGET
	make $(MAKE_OPTS) O=$(OUTPUT_DIR)/$(1) \
		BR2_EXTERNAL=$(PROJECT_DIR)/buildroot-ext \
		BR2_DL_DIR=$(DL_DIR) \
		BR2_CCACHE_DIR=$(CCACHE_DIR) \
		-C $(PROJECT_DIR)/buildroot $(2)
endef

define MAKE_IN_OUTPUT_DIR_WITH_TARGET
	make $(MAKE_OPTS) O=$(OUTPUT_DIR)/$(1) \
			-C $(OUTPUT_DIR)/$(1) \
			$(2)
endef

else # DOCKER_BUILD
	DOCKER         ?= docker

	ifndef BATCH_MODE
		DOCKER_OPTS += -i
	endif

	DOCKER_REPO    ?= harbor.spacemit.com/bianbu-linux
	IMAGE_NAME     ?= bianbu-linux-builder:latest

define RUN_DOCKER
	$(DOCKER) run -t --init --rm \
		-e HOME \
		-v $(PROJECT_DIR):/build \
		-v $(DL_DIR):/build/buildroot/dl \
		-v $(OUTPUT_DIR)/$*:/$* \
		-v $(CCACHE_DIR):$(HOME)/.buildroot-ccache \
		-w /$* \
		-v $(PROJECT_DIR)/.passwd:/etc/passwd:ro \
		-v $(PROJECT_DIR)/.group:/etc/group:ro \
		-u $(UID):$(GID) \
		$(DOCKER_OPTS) \
		$(DOCKER_REPO)/$(IMAGE_NAME)
endef

define MAKE_BUILDROOT
	$(RUN_DOCKER) make $(MAKE_OPTS) O=/$* \
			BR2_EXTERNAL=/build/buildroot-ext \
			-C /build/buildroot
endef

# Parameterized version of MAKE_BUILDROOT macro
define MAKE_BUILDROOT_WITH_TARGET
	$(DOCKER) run -t --init --rm \
		-e HOME \
		-v $(PROJECT_DIR):/build \
		-v $(DL_DIR):/build/buildroot/dl \
		-v $(OUTPUT_DIR)/$(1):/$(1) \
		-v $(CCACHE_DIR):$(HOME)/.buildroot-ccache \
		-w /$(1) \
		-v $(PROJECT_DIR)/.passwd:/etc/passwd:ro \
		-v $(PROJECT_DIR)/.group:/etc/group:ro \
		-u $(UID):$(GID) \
		$(DOCKER_OPTS) \
		$(DOCKER_REPO)/$(IMAGE_NAME) \
		make $(MAKE_OPTS) O=/$(1) \
			BR2_EXTERNAL=/build/buildroot-ext \
			-C /build/buildroot \
			$(2)
endef

define MAKE_IN_OUTPUT_DIR_WITH_TARGET
	$(DOCKER) run -t --init --rm \
		-e HOME \
		-v $(PROJECT_DIR):/build \
		-v $(DL_DIR):/build/buildroot/dl \
		-v $(OUTPUT_DIR)/$(1):/$(1) \
		-v $(CCACHE_DIR):$(HOME)/.buildroot-ccache \
		-w /$(1) \
		-v $(PROJECT_DIR)/.passwd:/etc/passwd:ro \
		-v $(PROJECT_DIR)/.group:/etc/group:ro \
		-u $(UID):$(GID) \
		$(DOCKER_OPTS) \
		$(DOCKER_REPO)/$(IMAGE_NAME) \
		make $(MAKE_OPTS) O=/$(1) \
			-C /$(1) \
			$(2)
endef

endif # DOCKER_BUILD

# Interactive configuration selection function (config and build)
define choose_config_and_build
	@echo "$(OK_COLOR)Available configs in $(CONFIG_DIRECTORY):$(NO_COLOR)"
	@i=1; \
	for file in $(CONFIGS); do \
		file_name=$$(basename "$$file"); \
		printf "  %d. %s\n" "$$i" "$$file_name"; \
		i=$$((i+1)); \
	done

	@echo ""
	@read -p "Your choice (1-$(NUM_CONFIGS)): " choice; \
	if [ "$$choice" -ge 1 -a "$$choice" -le $(NUM_CONFIGS) ]; then \
		selected_file=$$(echo $(CONFIGS) | cut -d ' ' -f $$choice); \
		printf "Selected: $$selected_file\n"; \
		file_name=$$(basename "$$selected_file"); \
		result=$$(echo "$$file_name" | sed -E 's/spacemit_(.*)_defconfig/\1/'); \
		mkdir -p output/$$result; \
		$(call MAKE_BUILDROOT_WITH_TARGET,$$result,$$file_name); \
		touch env.mk; \
		echo "# Current active configuration - Do not modify this section manually" > env.mk; \
		echo "CONFIG_NAME=$$result" >> env.mk; \
		echo "MAKEFILE=output/$$result/Makefile" >> env.mk; \
		echo "$(OK_COLOR)Configuration completed! Starting build...$(NO_COLOR)"; \
		$(call MAKE_BUILDROOT_WITH_TARGET,$$result,); \
	else \
		echo "Invalid choice: $$choice"; \
	fi
endef


.PHONY: all envconfig vars status build-docker-image bianbu-docker-image update-docker-image publish-docker-image \
        ccache-dir dl-dir

# Default target - must be first in file
ifneq ($(wildcard env.mk),)
all:
	@if [ ! -d "$(output_dir)" ]; then \
		echo "$(ERROR_COLOR)Error: env.mk exists but output directory '$(output_dir)' does not exist.$(NO_COLOR)"; \
		echo "$(WARN_COLOR)Please run 'make envconfig' to reconfigure the environment.$(NO_COLOR)"; \
		exit 1; \
	fi
	@echo "$(OK_COLOR)Passing target '$@' to $(output_dir)$(NO_COLOR)";
	@$(call MAKE_IN_OUTPUT_DIR_WITH_TARGET,$(CONFIG_NAME),$(MAKEOVERRIDES));
else
all: vars
endif

vars:
	@echo "$(OK_COLOR)Bianbu Linux Build System$(NO_COLOR)"
	@echo ""
	@echo "$(WARN_COLOR)Project Information:$(NO_COLOR)"
	@echo "  Project directory:  $(PROJECT_DIR)"
	@echo "  Download directory: $(DL_DIR)"
	@echo "  Output directory:   $(OUTPUT_DIR)"
	@echo "  ccache directory:   $(CCACHE_DIR)"
ifndef DIRECT_BUILD
	@echo "  Docker repo/image:  $(DOCKER_REPO)/$(IMAGE_NAME)"
	@echo "  Docker options:     $(DOCKER_OPTS)"
endif
	@echo "  Make options:       $(MAKE_OPTS)"
	@echo "  Current config:     $(CONFIG_NAME)"

status:
	@echo "$(OK_COLOR)=== Environment Status ===$(NO_COLOR)"
	@echo ""
	@echo "$(WARN_COLOR)Dependencies:$(NO_COLOR)"
	@command -v docker >/dev/null 2>&1 && echo "  $(CHECK_OK) Docker" || echo "  $(CHECK_FAIL) Docker"
	@command -v make >/dev/null 2>&1 && echo "  $(CHECK_OK) Make" || echo "  $(CHECK_FAIL) Make"
	@command -v git >/dev/null 2>&1 && echo "  $(CHECK_OK) Git" || echo "  $(CHECK_FAIL) Git"
	@echo ""
	@echo "$(WARN_COLOR)Docker Image:$(NO_COLOR)"
	@if docker images | grep -q "$(DOCKER_REPO)/$(IMAGE_NAME)"; then \
		echo "  $(CHECK_OK) Build image available"; \
		echo ""; \
		docker images $(DOCKER_REPO)/$(IMAGE_NAME) --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" | sed 's/^/    /'; \
	else \
		echo "  $(CHECK_FAIL) Build image not found"; \
		echo "    Run 'make build-docker-image' to create the image"; \
	fi

.check-docker-permission:
	@if ! docker info >/dev/null 2>&1; then \
		echo "$(WARN_COLOR)Cannot access Docker daemon$(NO_COLOR)"; \
		echo "Try adding your user to the docker group:"; \
		echo "  sudo usermod -aG docker \$$USER"; \
		echo "  newgrp docker"; \
		exit 1; \
	fi
	@touch .check-docker-permission

.check-docker:
	$(if $(shell which $(DOCKER) 2>/dev/null),, $(error "$(DOCKER) not found!"))
	@touch .check-docker

build-docker-image: .check-docker
	$(if $(DIRECT_BUILD),$(error "This is a direct build environment"))
	$(DOCKER) build scripts -t $(DOCKER_REPO)/$(IMAGE_NAME)
	@touch .bianbu-docker-image-available


$(PROJECT_DIR)/.passwd $(PROJECT_DIR)/.group:
	@current_user="$(shell whoami):x:$(UID):$(GID):$(shell whoami),,,:/home/$(shell whoami):/bin/bash"; \
	current_group="$(shell id -gn):x:$(GID):"; \
	if [ ! -f $(PROJECT_DIR)/.passwd ] || \
	   [ ! -f $(PROJECT_DIR)/.group ] || \
	   [ "$$current_user" != "$$(grep "^$(shell whoami):" $(PROJECT_DIR)/.passwd 2>/dev/null)" ] || \
	   [ "$$current_group" != "$$(grep "^$(shell id -gn):" $(PROJECT_DIR)/.group 2>/dev/null)" ]; then \
		echo "Updating .passwd .group files..."; \
		cp /etc/passwd $(PROJECT_DIR)/.passwd.tmp; \
		cp /etc/group $(PROJECT_DIR)/.group.tmp; \
		if ! grep -q "^$(shell whoami):" $(PROJECT_DIR)/.passwd.tmp; then \
			echo "$$current_user" >> $(PROJECT_DIR)/.passwd.tmp; \
		fi; \
		if ! grep -q "^$(shell id -gn):" $(PROJECT_DIR)/.group.tmp; then \
			echo "$$current_group" >> $(PROJECT_DIR)/.group.tmp; \
		fi; \
		mv $(PROJECT_DIR)/.passwd.tmp $(PROJECT_DIR)/.passwd; \
		mv $(PROJECT_DIR)/.group.tmp $(PROJECT_DIR)/.group; \
	fi

.bianbu-docker-image-available: .check-docker-permission .check-docker $(PROJECT_DIR)/.passwd $(PROJECT_DIR)/.group
	@$(DOCKER) pull $(DOCKER_REPO)/$(IMAGE_NAME) 2>/dev/null || \
	(echo "Image not found in registry, building locally..." && \
	 $(DOCKER) build scripts -t $(DOCKER_REPO)/$(IMAGE_NAME))
	@touch .bianbu-docker-image-available

bianbu-docker-image: $(if $(DIRECT_BUILD),,.bianbu-docker-image-available)

update-docker-image: .check-docker
	$(if $(DIRECT_BUILD),$(error "This is a direct build environment"))
	-@rm .bianbu-docker-image-available > /dev/null 2>&1
	@$(MAKE) bianbu-docker-image

publish-docker-image: .check-docker
	$(if $(DIRECT_BUILD),$(error "This is a direct build environment"))
	@$(DOCKER) push $(DOCKER_REPO)/$(IMAGE_NAME)

%-supported:
	$(if $(findstring $*, $(TARGETS)),,$(error "$* not supported!"))

output-dir-%: %-supported
	@mkdir -p $(OUTPUT_DIR)/$*

ccache-dir:
	@mkdir -p $(CCACHE_DIR)

dl-dir:
	@mkdir -p $(DL_DIR)

%-shell: bianbu-docker-image output-dir-%
	$(if $(DIRECT_BUILD),$(error "This is a direct build environment"))
	$(if $(BATCH_MODE),$(if $(CMD),,$(error "not supported in BATCH_MODE if CMD not specified!")),)
	@$(RUN_DOCKER) $(CMD)

envconfig: bianbu-docker-image ccache-dir dl-dir
	$(call choose_config_and_build)

ifneq ($(wildcard env.mk),) # Compatible old targets
MAKEFILE_PATH := $(shell grep "^MAKEFILE=" env.mk 2>/dev/null | cut -d'=' -f2)
output_dir := $(shell dirname $(MAKEFILE_PATH))
%: bianbu-docker-image ccache-dir dl-dir
# fix distclean in docker
	@if [ "$@" = "Makefile" ]; then \
		:; \
	elif [ "$@" = "distclean" ]; then \
		if [ "$(OUTPUT_DIR)/$(CONFIG_NAME)" = "$(PROJECT_DIR)/output/$(CONFIG_NAME)" ]; then \
			echo "rm -rf $(OUTPUT_DIR)/$(CONFIG_NAME)"; \
			rm -rf $(OUTPUT_DIR)/$(CONFIG_NAME); \
		fi; \
		echo "rm -rf $(DL_DIR)"; \
		rm -rf $(DL_DIR); \
	else \
		if [ ! -d "$(output_dir)" ]; then \
			echo "$(ERROR_COLOR)Error: env.mk exists but output directory '$(output_dir)' does not exist.$(NO_COLOR)"; \
			echo "$(WARN_COLOR)Please run 'make envconfig' to reconfigure the environment.$(NO_COLOR)"; \
			exit 1; \
		fi; \
		echo "$(OK_COLOR)Passing target '$@' to $(output_dir)$(NO_COLOR)"; \
		$(call MAKE_IN_OUTPUT_DIR_WITH_TARGET,$(CONFIG_NAME),$@ $(MAKEOVERRIDES)); \
	fi;
else # NEW TARGETS
%-clean: bianbu-docker-image output-dir-%
	@$(MAKE_BUILDROOT) clean

%-config: bianbu-docker-image output-dir-%
	@$(MAKE_BUILDROOT) spacemit_$*_defconfig

%-menuconfig: bianbu-docker-image %-config ccache-dir dl-dir
	@$(MAKE_BUILDROOT) menuconfig

%-build: bianbu-docker-image %-config ccache-dir dl-dir
	@$(MAKE_BUILDROOT) $(CMD)

%-source: bianbu-docker-image %-config ccache-dir dl-dir
	@$(MAKE_BUILDROOT) source

%-busybox-menuconfig: bianbu-docker-image %-config ccache-dir dl-dir
	@$(MAKE_BUILDROOT) busybox-menuconfig

%-uboot-menuconfig: bianbu-docker-image %-config ccache-dir dl-dir
	@$(MAKE_BUILDROOT) uboot-menuconfig

%-linux-menuconfig: bianbu-docker-image %-config ccache-dir dl-dir
	@$(MAKE_BUILDROOT) linux-menuconfig

%-cleanbuild: %-clean %-build
	@echo

%-pkg:
	$(if $(PKG),,$(error "PKG not specified!"))
	@$(MAKE) $*-build CMD=$(PKG)

%-build-cmd:
	@echo $(MAKE_BUILDROOT)

%-cleanbuild: %-clean %-build
	@echo

help:
	@echo "$(OK_COLOR)Bianbu Linux Build System - Help$(NO_COLOR)"
	@echo ""
	@echo "$(WARN_COLOR)Available solutions:$(NO_COLOR)"
	@echo "  $(OK_COLOR)$(TARGETS)$(NO_COLOR)"
	@echo ""
	@echo "$(WARN_COLOR)Development Commands:$(NO_COLOR)"
	@echo "  $(OK_COLOR)make vars$(NO_COLOR)                          # Show project information"
	@echo "  $(OK_COLOR)make <solution>-supported$(NO_COLOR)          # Check if solution is supported"
	@echo "  $(OK_COLOR)make <solution>-config$(NO_COLOR)             # Apply solution defconfig"
	@echo "  $(OK_COLOR)make <solution>-menuconfig$(NO_COLOR)         # Configure buildroot for solution"
	@echo "  $(OK_COLOR)make <solution>-linux-menuconfig$(NO_COLOR)   # Configure Linux kernel for solution"
	@echo "  $(OK_COLOR)make <solution>-uboot-menuconfig$(NO_COLOR)   # Configure U-Boot for solution"
	@echo "  $(OK_COLOR)make <solution>-busybox-menuconfig$(NO_COLOR) # Configure BusyBox for solution"
	@echo "  $(OK_COLOR)make <solution>-build$(NO_COLOR)              # Build specified solution"
	@echo "  $(OK_COLOR)make <solution>-pkg PKG=<package>$(NO_COLOR)  # Build specified package for solution"
	@echo "  $(OK_COLOR)make <solution>-shell$(NO_COLOR)              # Enter build container for solution"
	@echo "  $(OK_COLOR)make <solution>-source$(NO_COLOR)             # Download all source packages for solution"
	@echo "  $(OK_COLOR)make <solution>-clean$(NO_COLOR)              # Clean solution build artifacts"
	@echo "  $(OK_COLOR)make <solution>-cleanbuild$(NO_COLOR)         # Clean and rebuild solution"
	@echo "  $(OK_COLOR)make build-docker-image$(NO_COLOR)            # Build Docker image"
	@echo "  $(OK_COLOR)make update-docker-image$(NO_COLOR)           # Update Docker image"
	@echo ""
	@echo "$(OK_COLOR)Quick Start: Run 'make <solution>-build' to get started!$(NO_COLOR)"
endif # NEW TARGETS