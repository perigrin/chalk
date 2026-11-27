sub g { $_[0] .= "g" } sub f { goto &g } my $s="s"; f($s); print "$s\n";
