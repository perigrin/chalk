our $x=1; sub f { local $x=5; $_[0]=7; $x } my $r=f($x); print "$r$x\n";
