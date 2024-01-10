
# Makefile to config solution

DIRECTORY := buildroot-ext/configs/
OK_COLOR=\033[32;01m
# List all files in the directory
FILES := $(wildcard $(DIRECTORY)/*)
NUM_FILES := $(words $(FILES))

define choose_config
	@echo "Available configs in $(DIRECTORY):"
	@i=1; \
	for file in $(FILES); do \
		file_name=$$(basename "$$file"); \
		printf "  %d. %s\n" "$$i" "$$file_name"; \
		i=$$((i+1)); \
	done

	@echo "\n"
	@read -p "your choice (1-$(NUM_FILES)): " choice; \
	if [ "$$choice" -ge 1 -a "$$choice" -le $(NUM_FILES) ]; then \
		selected_file=$$(echo $(FILES) | cut -d ' ' -f $$choice); \
		printf "$$selected_file \n"; \
		file_name=$$(basename "$$selected_file"); \
		result=$$(echo "$$file_name" | sed -E 's/spacemit_(.*)_defconfig/\1/'); \
		mkdir -p output/$$result; \
		make -C ./buildroot O=../output/$$result BR2_EXTERNAL=../buildroot-ext  $$file_name; \
		touch env.mk; \
		echo "MAKEFILE=output/$$result/Makefile" > env.mk; \
		make -C output/$$result; \
	else \
		echo "Invalid choice: $$choice"; \
	fi
endef

ifeq ($(MAKECMDGOALS),envconfig)
.PHONY: envconfig
envconfig:
	$(call choose_config)
endif

ifeq ($(wildcard env.mk),)
all:
	$(call choose_config)

.PHONY: help
help:
	@echo "  envconfig - config solution env"
	@echo "  help - Display this help message"

else
include env.mk
include $(MAKEFILEls)
output_dir := $(shell dirname $(MAKEFILE))

all:
	$(MAKE) $(MAKECMDGOALS) -C $(output_dir)
%:
	$(MAKE) $(MAKECMDGOALS) -C $(output_dir)

endif
