# .bashrc

# Check if the session is non-interactive
if [[ $- != *i* ]]; then
    # If non-interactive, exit immediately
    return
fi

# Source global definitions
if [ -f /etc/bashrc ]; then
    . /etc/bashrc
fi

# User specific environment
if ! [[ "$PATH" =~ "$HOME/.local/bin:$HOME/bin:" ]]
then
    PATH="$HOME/.local/bin:$HOME/bin:$PATH"
fi
export PATH

# Enable bash completion
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# Uncomment the following line if you don't like systemctl's auto-paging feature:
# export SYSTEMD_PAGER=

# User specific aliases and functions
export EZA_COLORS="uu=0:gu=0"
alias la='eza -lgA'
alias ls='eza -lg'
alias grep='grep --color=auto'
alias df='duf'
alias top='btop'
alias cat='bat'
#alias cat='batcat'
alias da='date "+%d-%m-%Y %A %T %Z"'

# Allow sudo to run our aliases
# https://www.baeldung.com/linux/sudo-alias
alias sudo='sudo '

# Search command line history
alias h="history | grep "

alias openports='sudo netstat -nape --inet'
alias listen='sudo netstat -tulpn | grep LISTEN'

# Aliases for archives
alias mktar='tar -cvf'
alias mkbz2='tar -cvjf'
alias mkgz='tar -cvzf'
alias untar='tar -xvf'
alias unbz2='tar -xvjf'
alias ungz='tar -xvzf'

source /usr/share/autojump/autojump.bash

#source ./.bash_git.sh
#export PS1='\[\033[01;30m\]\t `if [ $? = 0 ]; then echo "\[\033[01;32m\]ツ"; else echo "\[\033[01;31m\]✗"; fi` \[\033[00;32m\]\h\[\033[00;37m\]:\[\033[31m\]$(__git_ps1 "(%s)\[\033[01m\]")\[\033[00;34m\]\w\[\033[00m\] >'

export PS1='\[\033[01;30m\]\t `if [ $? = 0 ]; then echo "\[\033[01;32m\]ツ"; else echo "\[\033[01;31m\]✗"; fi` \[\033[00;32m\]\h\[\033[00;37m\]:\[\033[31m\]\[\033[00;34m\]\w\[\033[00m\] >'

neofetch
