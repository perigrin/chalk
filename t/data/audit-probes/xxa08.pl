sub g { $_[0] .= "g" } sub f { g($_[0]); g(@_) } my $s="s"; f($s); print "$s\n";
