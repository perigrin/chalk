our $g=1; sub f { local $g=2; no strict 'refs'; &{"nope"}() } eval { f() }; print "$g ", $@?1:0, "\n";
