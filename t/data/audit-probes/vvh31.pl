$@ = "old"; eval { 1 }; print $@ eq "" ? "cleared" : $@, "\n";
