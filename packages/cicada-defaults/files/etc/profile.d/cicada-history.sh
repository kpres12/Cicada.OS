# Shell history is a forensic artifact, not a feature.
# A live-response examiner reads ~/.bash_history for every user (root included)
# to reconstruct what was typed. Cicada keeps history in RAM for the session
# and never writes it to disk.
HISTFILE=/dev/null
HISTSIZE=1000
HISTFILESIZE=0
HISTCONTROL=ignoreboth
export HISTFILE HISTSIZE HISTFILESIZE HISTCONTROL

# zsh/ksh use different names for the same thing.
SAVEHIST=0
export SAVEHIST
