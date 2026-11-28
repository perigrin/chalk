my @a = (1,2); use constant L => -1; sub f { $a[L] = 5; $_[0] } print f($a[1]), "\n";
