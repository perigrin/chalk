my $x=1; sub f { $x=2; return $_[0] } my $v=f($x); print "$v\n";
