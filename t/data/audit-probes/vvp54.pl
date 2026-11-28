my @a = (1,2); sub f { $a[-2] = 5; my $v = shift; $v } print f($a[0]), "\n";
