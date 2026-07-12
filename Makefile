# ═════════════════════════════════════════════════════════════════════════════
# Super Minimal Linux Libre — Cross-Compilation Build System
# ═════════════════════════════════════════════════════════════════════════════
#
# Split into modular .mk files under mk/
#   make help  — shows all targets
#   make all   — build all userland packages
# ═════════════════════════════════════════════════════════════════════════════

include mk/00-vars.mk
include mk/01-setup.mk
include mk/02-fake-bin.mk
include mk/03-source-prep.mk
include mk/04-build-rules.mk
include mk/05-packages.mk
include mk/07-kernel.mk
include mk/08-clean-help.mk
include mk/09-init.mk
include mk/10-disk.mk
include mk/11-test.mk
