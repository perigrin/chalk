my @a = (1,2,3); sub f { $_[0] } my @o; for my $x (@a) { my $v = f($x); $x = 0; push @o, $v } print "@o|@a\n";
