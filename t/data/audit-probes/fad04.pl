our $g=0; sub f { for my $i (1..3) { local $g=$i; die "x\n" if $i==2 } } eval { f() }; print "$g\n";
