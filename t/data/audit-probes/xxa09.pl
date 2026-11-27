sub g { $_[0] .= "g" } sub f { &g } my $s="s"; f($s); print "$s\n";
