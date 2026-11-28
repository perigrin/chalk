our $x = 1; *x = \"abc"; eval { $x = 2 }; print $@ ? "died" : "ok", "$x\n";
