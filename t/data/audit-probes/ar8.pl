sub f { $_[0] = 7 } sub g { f($_[0]) } my $x = 1; g($x); print "$x\n";
