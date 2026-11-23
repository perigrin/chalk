our $g=1; sub f { local $g=2; my $o=shift; $o->nope } eval { f("K") }; print "$g\n";
