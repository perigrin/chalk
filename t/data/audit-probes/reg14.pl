my $x=1; sub f { $x=5; 1 } my $v = $x + f() + $x; print "$v\n";
