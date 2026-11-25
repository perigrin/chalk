our $g=1; sub f { local $g=2; die "x\n" } for (1..2) { eval { f() }; print $g } print "\n";
