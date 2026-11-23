our $g=1; sub f { local $g=2; return $g+1 } my $v=f(); print "$v $g\n";
