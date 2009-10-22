security find-generic-password -s SSH | grep "\"acct\"<blob>" | sed -e 's/^.*"acct"<blob>=\(".*"\)$/\1/'
