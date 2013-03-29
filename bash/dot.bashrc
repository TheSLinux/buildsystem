#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto --indicator-style=classify'
alias grep='grep --color'

export PS1='\[\e[0;32m\]:: \[\e[0;37m\]You are \[\e[0;31m\]\u\[\e[0;37m\] in \[\e[0;31m\]\h\[\e[0;37m\]:\[\e[0;34m\]\w\n\[\e[0;32m\]\$\[\e[0m\] '
export EDITOR=nano
