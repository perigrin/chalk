my @a=(1,2); sub f { my $r=[@_]; $a[0]=9; "@$r" } print f(@a), "\n";
