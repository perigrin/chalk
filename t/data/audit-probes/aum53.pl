my @l = (" a ", "b "); sub trim { s/^\s+|\s+$//g } trim() for @l; print join("|", @l), "\n";
