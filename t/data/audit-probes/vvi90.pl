for (my @t = ("a ", " b")) { s/^\s+|\s+$//g } my @t = ("a ", " b"); s/^\s+|\s+$//g for @t; print join("|", @t), "\n";
