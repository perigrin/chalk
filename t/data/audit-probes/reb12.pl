our $g=1; sub f { local $g=2; for my $i (1..3) { return $i if $i==2 } 0 } my $v=f(); print "$v $g\n";
