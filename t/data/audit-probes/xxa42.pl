sub f { return if $_[1] > 2; $_[0] .= $_[1]; f($_[0], $_[1]+1) } my $s=""; f($s,0); print "$s\n";
