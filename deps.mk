## Installed dependencies
# This framework will automatically install build-time dependencies as a
# prerequisite for build targets.  This installation uses local directories
# (usually under lib/) to store all installed software.
#
# Some dependencies are defined in the framework and will always be installed.
# This includes xml2rfc and kramdown-rfc.  Other dependencies are specific to a
# particular project and will be driven from files that are in the project
# repository.
#
# Currently, this supports three different package installation frameworks:
# * pip for python, specified in requirements.txt
# * gem for ruby, specified in Gemfile
# * npm for nodejs, specified in package.json
# Each system has its own format for specifying dependencies.  What you need to
# know is that if you include any of the above files, you don't need to worry
# about ensuring that these tools are available when a build runs.
#
# This also works in CI runs, with caching, so your builds won't run too slowly.
# The prerequsites that are installed by default are installed globally in a CI
# docker image, which avoids an expensive installation step in CI.  This makes
# CI runs slightly different than local runs.
#
# For python, if you have some extra tools, just add them to requirements.txt
# and they will be installed into a virtual environment.
#
# For ruby, listing tools in a `Gemfile` will ensure that files are installed.
# You should add `Gemfile.lock` to your .gitignore file if you do this.
#
# For nodejs, new dependencies can be added to `package.json`.  Use `npm install
# -s <package>` to add files.  You should add `package-lock.json` and
# `node_modules/` to your `.gitignore` file if you do this.
#
# Tools are added to the path, so you should have no problem running them.

DEPS_FILES :=
.PHONY: deps clean-deps update-deps

## Python
ifeq (true,$(CI))
# Override BUNDLE_PATH so we can use caching in CI.
VENVDIR = $(realpath .)/.venv
endif
VENVDIR ?= $(realpath $(LIBDIR))/.venv
REQUIREMENTS_TXT := $(wildcard requirements.txt)
ifneq (,$(strip $(REQUIREMENTS_TXT)))
# Need to maintain a local marker file in case the lib/ directory is shared.
LOCAL_VENV := .requirements.txt
endif
ifneq (true,$(CI))
# Don't install from lib/requirements.txt in CI; these are in the docker image.
REQUIREMENTS_TXT += $(LIBDIR)/requirements.txt
endif
ifneq (,$(strip $(REQUIREMENTS_TXT)))
# We have something to install, so include venv.mk.
include $(LIBDIR)/venv.mk
export PATH := $(VENV):$(PATH)

ifneq (,$(LOCAL_VENV))
DEPS_FILES += $(LOCAL_VENV)
$(LOCAL_VENV): $(VENV)/$(MARKER)
	@touch $@
else
DEPS_FILES += $(VENV)/$(MARKER)
endif

update-deps::
	pip install --upgrade --upgrade-strategy eager $(foreach path,$(REQUIREMENTS_TXT),-r $(path))

clean-deps:: clean-venv

endif

# Now set variables based on environment.
ifneq (true,$(CI))
export VENV
python := $(VENV)/python
xml2rfc := $(VENV)/xml2rfc $(xml2rfcargs)
rfc-tidy := $(VENV)/rfc-tidy
else
python ?= python3
xml2rfc ?= xml2rfc $(xml2rfcargs)
rfc-tidy ?= rfc-tidy
endif

## Ruby
ifeq (,$(shell which bundle))
$(warning ruby bundler not installed; skipping bundle install)
NO_RUBY := true
endif

ifneq (true,$(NO_RUBY))
ifeq (true,$(CI))
# Override BUNDLE_PATH so we can use caching in CI.
BUNDLE_PATH := $(realpath .)/.gems
endif
export BUNDLE_PATH ?= $(realpath $(LIBDIR))/.gems
# Install binaries to somewhere sensible instead of .../ruby/$v/bin where $v
# doesn't even match the current ruby version.
export BUNDLE_BIN := $(BUNDLE_PATH)/bin
export PATH := $(BUNDLE_BIN):$(PATH)

ifneq (,$(wildcard Gemfile))
# A local Gemfile exists.
DEPS_FILES += $(BUNDLE_PATH)/.i-d-template.opt
$(BUNDLE_PATH)/.i-d-template.opt: Gemfile.lock
	@touch $@

Gemfile.lock: Gemfile
	bundle install --gemfile=$(realpath $<)
	@touch $@

update-deps:: Gemfile
	bundle update --gemfile=$(realpath $<)

clean-deps::
	-rm -rf $(BUNDLE_PATH)
endif # Gemfile

ifneq (true,$(CI))
# Install kramdown-rfc.
DEPS_FILES += $(BUNDLE_PATH)/.i-d-template.core
$(BUNDLE_PATH)/.i-d-template.core: $(LIBDIR)/Gemfile.lock
	@touch $@

$(LIBDIR)/Gemfile.lock: $(LIBDIR)/Gemfile
	bundle install --gemfile=$(realpath $<)
	@touch $@

update-deps:: $(LIBDIR)/Gemfile
	bundle update --gemfile=$(realpath $<)

clean-deps::
	-rm -rf $(BUNDLE_PATH)
endif # !CI
endif # !NO_RUBY

## Nodejs
ifeq (,$(shell which npm))
ifneq (,$(wildcard package.json))
$(warning package.json exists, but npm not available; npm packages not installed)
endif
NO_NODEJS := true
endif

ifneq (true,$(NO_NODEJS))
ifneq (,$(wildcard package.json))
export PATH := $(abspath node_modules/.bin):$(PATH)
DEPS_FILES += package-lock.json
package-lock.json: package.json
	npm install
	@touch $@

update-deps::
	npm update --no-save --dev

clean-deps::
	-rm -rf package-lock.json
endif # package.json
endif # !NO_NODEJS

## Link everything up
deps:: $(DEPS_FILES)

update-deps::

clean-deps::
	@-rm -f $(DEPS_FILES)
