my @a = (1,2); my $i = 0; sub f { $i = 1; $_[0] } print f($a[$i]), "\n";
