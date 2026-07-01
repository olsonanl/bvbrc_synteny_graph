TOP_DIR = ../..
include $(TOP_DIR)/tools/Makefile.common

THIS_APP = $(shell basename $(shell pwd))

# --- PANACONDA / PYTHON DEPENDENCIES ---
# Cloned and pip-installed from a local checkout rather than via "pip install
# git+...": the upstream repo has a stray gitlink (layout/pangenome_layout, mode
# 160000) with no matching entry in .gitmodules, so pip's mandatory
# "git submodule update --init --recursive" aborts. A plain clone skips submodule
# init, and a local pip install never touches submodules. The package itself is a
# single pure-Python module (src/fam_to_graph.py) and needs neither submodule.
PANACONDA_REPO = https://github.com/BV-BRC-dependencies/pangenome_graphs.git
# NOTE: Update version tag if necessary
LAYOUT_JAR_URL = https://github.com/aswarren/pangenome_layout/releases/download/initial/gexf_layout.jar

BUILD_VENV = $(shell pwd)/venv
TARGET_VENV = $(TARGET)/venv/$(THIS_APP)

DEPLOY_RUNTIME ?= /kb/runtime
TARGET ?= /kb/deployment

APP_SERVICE = app_service

SRC_PERL = $(wildcard scripts/*.pl)
BIN_PERL = $(addprefix $(BIN_DIR)/,$(basename $(notdir $(SRC_PERL))))
DEPLOY_PERL = $(addprefix $(TARGET)/bin/,$(basename $(notdir $(SRC_PERL))))

SRC_SERVICE_PERL = $(wildcard service-scripts/*.pl)
BIN_SERVICE_PERL = $(addprefix $(BIN_DIR)/,$(basename $(notdir $(SRC_SERVICE_PERL))))
DEPLOY_SERVICE_PERL = $(addprefix $(SERVICE_DIR)/bin/,$(basename $(notdir $(SRC_SERVICE_PERL))))

CLIENT_TESTS = $(wildcard t/client-tests/*.t)
SERVER_TESTS = $(wildcard t/server-tests/*.t)
PROD_TESTS = $(wildcard t/prod-tests/*.t)

STARMAN_WORKERS = 8
STARMAN_MAX_REQUESTS = 100

TPAGE_ARGS = --define kb_top=$(TARGET) --define kb_runtime=$(DEPLOY_RUNTIME) --define kb_service_name=$(SERVICE) \
	--define kb_service_port=$(SERVICE_PORT) --define kb_service_dir=$(SERVICE_DIR) \
	--define kb_sphinx_port=$(SPHINX_PORT) --define kb_sphinx_host=$(SPHINX_HOST) \
	--define kb_starman_workers=$(STARMAN_WORKERS) \
	--define kb_starman_max_requests=$(STARMAN_MAX_REQUESTS)

all: bin 

bin: venv $(BIN_PERL) $(BIN_SERVICE_PERL)


# --- LOCAL BUILD ENVIRONMENT ---
.PHONY: venv
venv:
	rm -rf $(BUILD_VENV)
	python3 -m venv $(BUILD_VENV)
	rm -rf $(BUILD_VENV)/pangenome_graphs.src
	git clone $(PANACONDA_REPO) $(BUILD_VENV)/pangenome_graphs.src
	. $(BUILD_VENV)/bin/activate; pip3 install $(BUILD_VENV)/pangenome_graphs.src
	wget -qO $(BUILD_VENV)/bin/gexf_layout.jar $(LAYOUT_JAR_URL) || curl -L -o $(BUILD_VENV)/bin/gexf_layout.jar $(LAYOUT_JAR_URL)
	# BV-BRC Hygiene: Isolate the app executables from the venv's python binaries
	mkdir -p $(BUILD_VENV)/app-bin
	ln -s ../bin/panaconda ../bin/gexf_layout.jar $(BUILD_VENV)/app-bin

deploy: deploy-all
deploy-all: deploy-client deploy-service
deploy-client: deploy-libs deploy-scripts deploy-docs

deploy-service: deploy-libs deploy-scripts deploy-custom-service-scripts deploy-specs deploy-venv


# --- TARGET DEPLOYMENT ENVIRONMENT ---
deploy-venv:
	rm -rf $(TARGET_VENV)
	$(DEPLOY_RUNTIME)/bin/python3 -m venv $(TARGET_VENV)
	rm -rf $(TARGET_VENV)/pangenome_graphs.src
	git clone $(PANACONDA_REPO) $(TARGET_VENV)/pangenome_graphs.src
	. $(TARGET_VENV)/bin/activate; pip3 install $(TARGET_VENV)/pangenome_graphs.src
	wget -qO $(TARGET_VENV)/bin/gexf_layout.jar $(LAYOUT_JAR_URL) || curl -L -o $(TARGET_VENV)/bin/gexf_layout.jar $(LAYOUT_JAR_URL)
	# BV-BRC Hygiene: Isolate the app executables from the venv's python binaries
	mkdir -p $(TARGET_VENV)/app-bin
	ln -s ../bin/panaconda ../bin/gexf_layout.jar $(TARGET_VENV)/app-bin

deploy-specs:
	mkdir -p $(TARGET)/services/$(APP_SERVICE)
	rsync -arv app_specs $(TARGET)/services/$(APP_SERVICE)/.

deploy-custom-service-scripts:
	export KB_TOP=$(TARGET); \
	export KB_RUNTIME=$(DEPLOY_RUNTIME); \
	export KB_PERL_PATH=$(TARGET)/lib ; \
	export PATH_ADDITIONS=$(TARGET_VENV)/app-bin; \
	export WRAP_VARIABLES=PANACONDA_LAYOUT_JAR; \
	export PANACONDA_LAYOUT_JAR=$(TARGET_VENV)/bin/gexf_layout.jar; \
	for src in $(SRC_SERVICE_PERL) ; do \
	        basefile=`basename $$src`; \
	        base=`basename $$src .pl`; \
	        echo install $$src $$base ; \
	        cp $$src $(TARGET)/plbin ; \
	        $(WRAP_PERL_SCRIPT) "$(TARGET)/plbin/$$basefile" $(TARGET)/bin/$$base ; \
	done

$(BIN_DIR)/%: service-scripts/%.pl $(TOP_DIR)/user-env.sh
	export PATH_ADDITIONS=$(BUILD_VENV)/app-bin; \
	$(WRAP_PERL_SCRIPT) '$$KB_TOP/modules/$(CURRENT_DIR)/$<' $@

$(BIN_DIR)/%: service-scripts/%.py $(TOP_DIR)/user-env.sh
	export PATH_ADDITIONS=$(BUILD_VENV)/app-bin; \
	$(WRAP_PYTHON_SCRIPT) '$$KB_TOP/modules/$(CURRENT_DIR)/$<' $@

deploy-dir:
	if [ ! -d $(SERVICE_DIR) ] ; then mkdir $(SERVICE_DIR) ; fi
	if [ ! -d $(SERVICE_DIR)/bin ] ; then mkdir $(SERVICE_DIR)/bin ; fi

deploy-docs: 

clean:
	rm -rf $(BUILD_VENV)

# --- WRAP LOCAL SCRIPTS ---
$(BIN_DIR)/%: service-scripts/%.pl $(TOP_DIR)/user-env.sh
	export PATH_ADDITIONS=$(BUILD_VENV)/bin; \
	$(WRAP_PERL_SCRIPT) '$$KB_TOP/modules/$(CURRENT_DIR)/$<' $@

$(BIN_DIR)/%: service-scripts/%.py $(TOP_DIR)/user-env.sh
	export PATH_ADDITIONS=$(BUILD_VENV)/bin; \
	$(WRAP_PYTHON_SCRIPT) '$$KB_TOP/modules/$(CURRENT_DIR)/$<' $@

include $(TOP_DIR)/tools/Makefile.common.rules
