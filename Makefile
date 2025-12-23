# Enhanced Makefile with Docker support for Buildroot Development

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
	$(DOCKER) run -t --init --rm --security-opt seccomp=unconfined \
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
	$(DOCKER) run -t --init --rm --security-opt seccomp=unconfined \
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
	$(DOCKER) run -t --init --rm --security-opt seccomp=unconfined \
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
	@printf "$(OK_COLOR)Available configs in $(CONFIG_DIRECTORY):$(NO_COLOR)\n"
	@i=1; \
	for file in $(CONFIGS); do \
		file_name=$$(basename "$$file"); \
		printf "  %d. %s\n" "$$i" "$$file_name"; \
		i=$$((i+1)); \
	done

	@printf "\n"
	@read -p "Your choice (1-$(NUM_CONFIGS)): " choice; \
	if [ "$$choice" -ge 1 -a "$$choice" -le $(NUM_CONFIGS) ]; then \
		selected_file=$$(echo $(CONFIGS) | cut -d ' ' -f $$choice); \
		printf "Selected: $$selected_file\n"; \
		file_name=$$(basename "$$selected_file"); \
		result=$$(echo "$$file_name" | sed -E 's/spacemit_(.*)_defconfig/\1/'); \
		mkdir -p output/$$result; \
		$(call MAKE_BUILDROOT_WITH_TARGET,$$result,$$file_name); \
		touch env.mk; \
		printf "# Current active configuration - Do not modify this section manually\n" > env.mk; \
		printf "CONFIG_NAME=$$result\n" >> env.mk; \
		printf "MAKEFILE=output/$$result/Makefile\n" >> env.mk; \
		printf "$(OK_COLOR)Configuration completed! Starting build...$(NO_COLOR)\n"; \
		$(call MAKE_BUILDROOT_WITH_TARGET,$$result,); \
	else \
		printf "Invalid choice: $$choice\n"; \
	fi
endef


.PHONY: all envconfig vars status build-docker-image bianbu-docker-image update-docker-image publish-docker-image \
		ccache-dir dl-dir

# Default target - must be first in file
ifneq ($(wildcard env.mk),)
all:
	@if [ ! -d "$(output_dir)" ]; then \
		printf "$(ERROR_COLOR)Error: env.mk exists but output directory '$(output_dir)' does not exist.$(NO_COLOR)\n"; \
		printf "$(WARN_COLOR)Please run 'make envconfig' to reconfigure the environment.$(NO_COLOR)\n"; \
		exit 1; \
	fi
	@printf "$(OK_COLOR)Passing target '$@' to $(output_dir)$(NO_COLOR)\n";
	@$(call MAKE_IN_OUTPUT_DIR_WITH_TARGET,$(CONFIG_NAME),$@ $(MAKEOVERRIDES));
else
all: vars
endif

vars:
	@printf "$(OK_COLOR)Buildroot Build System$(NO_COLOR)\n"
	@printf "\n"
	@printf "$(WARN_COLOR)Project Information:$(NO_COLOR)\n"
	@printf "  Project directory:  $(PROJECT_DIR)\n"
	@printf "  Download directory: $(DL_DIR)\n"
	@printf "  Output directory:   $(OUTPUT_DIR)\n"
	@printf "  ccache directory:   $(CCACHE_DIR)\n"
ifndef DIRECT_BUILD
	@printf "  Docker repo/image:  $(DOCKER_REPO)/$(IMAGE_NAME)\n"
	@printf "  Docker options:     $(DOCKER_OPTS)\n"
endif
	@printf "  Make options:       $(MAKE_OPTS)\n"
	@printf "  Current config:     $(CONFIG_NAME)\n"

status:
	@printf "$(OK_COLOR)=== Environment Status ===$(NO_COLOR)\n"
	@printf "\n"
	@printf "$(WARN_COLOR)Dependencies:$(NO_COLOR)\n"
	@command -v docker >/dev/null 2>&1 && printf "  $(CHECK_OK) Docker\n" || printf "  $(CHECK_FAIL) Docker\n"
	@command -v make >/dev/null 2>&1 && printf "  $(CHECK_OK) Make\n" || printf "  $(CHECK_FAIL) Make\n"
	@command -v git >/dev/null 2>&1 && printf "  $(CHECK_OK) Git\n" || printf "  $(CHECK_FAIL) Git\n"
	@printf "\n"
	@printf "$(WARN_COLOR)Docker Image:$(NO_COLOR)\n"
	@if docker images | grep -q "$(DOCKER_REPO)/$(IMAGE_NAME)"; then \
		printf "  $(CHECK_OK) Build image available\n"; \
		printf "\n"; \
		docker images $(DOCKER_REPO)/$(IMAGE_NAME) --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}" | sed 's/^/    /'; \
	else \
		printf "  $(CHECK_FAIL) Build image not found\n"; \
		printf "    Run 'make build-docker-image' to create the image\n"; \
	fi

.check-docker-permission:
	@if ! docker info >/dev/null 2>&1; then \
		printf "$(WARN_COLOR)Cannot access Docker daemon$(NO_COLOR)\n"; \
		printf "Try adding your user to the docker group:\n"; \
		printf "  sudo usermod -aG docker \$$USER\n"; \
		printf "  newgrp docker\n"; \
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
		printf "Updating .passwd .group files...\n"; \
		cp /etc/passwd $(PROJECT_DIR)/.passwd.tmp; \
		cp /etc/group $(PROJECT_DIR)/.group.tmp; \
		if ! grep -q "^$(shell whoami):" $(PROJECT_DIR)/.passwd.tmp; then \
			printf "$$current_user\n" >> $(PROJECT_DIR)/.passwd.tmp; \
		fi; \
		if ! grep -q "^$(shell id -gn):" $(PROJECT_DIR)/.group.tmp; then \
			printf "$$current_group\n" >> $(PROJECT_DIR)/.group.tmp; \
		fi; \
		mv $(PROJECT_DIR)/.passwd.tmp $(PROJECT_DIR)/.passwd; \
		mv $(PROJECT_DIR)/.group.tmp $(PROJECT_DIR)/.group; \
	fi

.bianbu-docker-image-available: .check-docker-permission .check-docker $(PROJECT_DIR)/.passwd $(PROJECT_DIR)/.group
	@$(DOCKER) pull $(DOCKER_REPO)/$(IMAGE_NAME) 2>/dev/null || \
	(printf "Image not found in registry, building locally...\n" && \
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
			printf "rm -rf $(OUTPUT_DIR)/$(CONFIG_NAME)\n"; \
			rm -rf $(OUTPUT_DIR)/$(CONFIG_NAME); \
		fi; \
		printf "rm -rf $(DL_DIR)\n"; \
		rm -rf $(DL_DIR); \
	else \
		if [ ! -d "$(output_dir)" ]; then \
			printf "$(ERROR_COLOR)Error: env.mk exists but output directory '$(output_dir)' does not exist.$(NO_COLOR)\n"; \
			printf "$(WARN_COLOR)Please run 'make envconfig' to reconfigure the environment.$(NO_COLOR)\n"; \
			exit 1; \
		fi; \
		printf "$(OK_COLOR)Passing target '$@' to $(output_dir)$(NO_COLOR)\n"; \
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
	@printf "\n"

%-pkg:
	$(if $(PKG),,$(error "PKG not specified!"))
	@$(MAKE) $*-build CMD=$(PKG)

%-build-cmd:
	@printf $(MAKE_BUILDROOT)

%-cleanbuild: %-clean %-build
	@printf "\n"

help:
	@printf "$(OK_COLOR)Buildroot Build System - Help$(NO_COLOR)\n"
	@printf "\n"
	@printf "$(WARN_COLOR)Available solutions:$(NO_COLOR)\n"
	@printf "  $(OK_COLOR)$(TARGETS)$(NO_COLOR)\n"
	@printf "\n"
	@printf "$(WARN_COLOR)Development Commands:$(NO_COLOR)\n"
	@printf "  $(OK_COLOR)make vars$(NO_COLOR)                          # Show project information\n"
	@printf "  $(OK_COLOR)make <solution>-supported$(NO_COLOR)          # Check if solution is supported\n"
	@printf "  $(OK_COLOR)make <solution>-config$(NO_COLOR)             # Apply solution defconfig\n"
	@printf "  $(OK_COLOR)make <solution>-menuconfig$(NO_COLOR)         # Configure buildroot for solution\n"
	@printf "  $(OK_COLOR)make <solution>-linux-menuconfig$(NO_COLOR)   # Configure Linux kernel for solution\n"
	@printf "  $(OK_COLOR)make <solution>-uboot-menuconfig$(NO_COLOR)   # Configure U-Boot for solution\n"
	@printf "  $(OK_COLOR)make <solution>-busybox-menuconfig$(NO_COLOR) # Configure BusyBox for solution\n"
	@printf "  $(OK_COLOR)make <solution>-build$(NO_COLOR)              # Build specified solution\n"
	@printf "  $(OK_COLOR)make <solution>-pkg PKG=<package>$(NO_COLOR)  # Build specified package for solution\n"
	@printf "  $(OK_COLOR)make <solution>-shell$(NO_COLOR)              # Enter build container for solution\n"
	@printf "  $(OK_COLOR)make <solution>-source$(NO_COLOR)             # Download all source packages for solution\n"
	@printf "  $(OK_COLOR)make <solution>-clean$(NO_COLOR)              # Clean solution build artifacts\n"
	@printf "  $(OK_COLOR)make <solution>-cleanbuild$(NO_COLOR)         # Clean and rebuild solution\n"
	@printf "  $(OK_COLOR)make build-docker-image$(NO_COLOR)            # Build Docker image\n"
	@printf "  $(OK_COLOR)make update-docker-image$(NO_COLOR)           # Update Docker image\n"
	@printf "\n"
	@printf "$(OK_COLOR)Quick Start: Run 'make <solution>-build' to get started, e.g.:$(NO_COLOR)\n"
	@printf "  make k3-build\n"
endif # NEW TARGETS