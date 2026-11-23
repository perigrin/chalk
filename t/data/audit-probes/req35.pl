our $g=1; sub f { local $g=2; my $r=shift; $r->() } eval { f(undef) }; print "$g\n";
