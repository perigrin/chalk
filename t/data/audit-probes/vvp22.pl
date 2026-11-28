my @a = (1,2); sub f { ($a[-2], my $t) = (5,6); $_[0] } print f($a[0]), "\n";
