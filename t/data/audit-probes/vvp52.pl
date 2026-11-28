my @a = (1,2); sub f { $a[-2] = 5; my $v = $_[0]; $v } print f($a[0]), "\n";
