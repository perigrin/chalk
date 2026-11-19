sub f { $_[0] = 7 } sub g { &f } my $x = 1; g($x); print "$x\n";
