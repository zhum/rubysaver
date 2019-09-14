#!/bin/sh

USE_RBENV=1
export HOME=/home/YOURNAME

cd /opt/rubysaver

if [ USE_RBENV = '1' ]; then
  export RBENV_ROOT="${HOME}/.rbenv"

  if [ -d "${RBENV_ROOT}" ]; then
    export PATH="${RBENV_ROOT}/bin:${PATH}"
    eval "$(rbenv init -)"
  fi

  rbenv exec bundle exec ruby ./rs.rb
else
  ./rs.rb
fi
