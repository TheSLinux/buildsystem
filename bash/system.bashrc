#
# /etc/bash.bashrc
#

# If not running interactively, don't do anything
[[ $- == *i* ]] || return 0

export PS1='\[\e[0;32m\]:: \[\e[0;37m\]You are \[\e[0;31m\]\u\[\e[0;37m\] in \[\e[0;31m\]\h\[\e[0;37m\]:\[\e[0;34m\]\w\n\[\e[0;32m\]#\[\e[0m\] '
export PS2='> '
export PS3='> '
export PS4='+ '
export EDITOR=nano

case ${TERM} in
  xterm*|rxvt*|Eterm|aterm|kterm|gnome*)
    PROMPT_COMMAND=${PROMPT_COMMAND:+$PROMPT_COMMAND; }'printf "\033]0;%s@%s:%s\007" "${USER}" "${HOSTNAME%%.*}" "${PWD/#$HOME/~}"'
    ;;

  screen)
    PROMPT_COMMAND=${PROMPT_COMMAND:+$PROMPT_COMMAND; }'printf "\033_%s@%s:%s\033\\" "${USER}" "${HOSTNAME%%.*}" "${PWD/#$HOME/~}"'
    ;;
esac

[[ ! -r /usr/share/bash-completion/bash_completion ]] \
  || . /usr/share/bash-completion/bash_completion
