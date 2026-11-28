eval { die "x\n" }; sub cl { eval { 1 } } cl(); print $@ eq "" ? "cleared" : $@, "\n";
