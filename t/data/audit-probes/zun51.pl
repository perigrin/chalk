our $g=1; sub f { local $g=5; g2() } sub g2 { die "z\n" if $g==5; 1 } eval { f() }; print "$g\n";
