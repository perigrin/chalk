our $g=1; sub f { local $g=2; my $x = sqrt($_[0]); 1 } eval { f(-1) }; print "$g\n";
