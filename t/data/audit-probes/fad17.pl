our $g=1; sub f { local $g=2; my @r=map { die "x\n" if $_==2; $_ } 1..3; @r } eval { f() }; print "$g\n";
