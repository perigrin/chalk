my @a = ([1],[2]); my $in = $a[0]; sub f { $in->[0] = 5; $_[0] } print f($a[0][0]), "\n";
