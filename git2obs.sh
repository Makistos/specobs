#!/bin/bash

# Script to import package from git and push it to OBS.

# Assumes current directory is a fresh OSC directory for the package

# Current directory name is the package name
PACKAGE=$(basename $(pwd))

# Fix this to point to a correct repository
REPO=git@gitorious.org:FOOBAR/FOOBAR.git

# Fix Ibuntu issues
umask 022

set -e

if [ ! -d .git ]; then
	# Setup structure
	git clone $REPO
	mv ${PACKAGE}/* ${PACKAGE}/.git* .
	rmdir ${PACKAGE}

	# Add .gitignore
	cat >> .gitignore <<EOF
*.tar.gz
*.tar.bz2
.osc
EOF

	git add .gitignore
	git commit -s -m "Add .gitignore" .gitignore
else
	git pull --rebase
fi

# Bump version
bump.pl

# Notify OSC about added/removed files
osc ar

# Commit to OBS
osc commit -m $(git tag -l | grep ^V | sort | tail -1)

# Push to git
git push --tags
git push

set +e
