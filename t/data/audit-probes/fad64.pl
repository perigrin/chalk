our $g="o"; sub f { local $g="i"; die "x\n" } for (1..2) { eval { f() }; $g.="+"; } print "$g\n";
