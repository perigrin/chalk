my @a = (1,2); my $i = 0; sub f { $a[$i] = 5; $_[0] } print f($a[0]), "\n";
