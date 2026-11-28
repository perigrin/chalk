my @a = (1,2); use constant Z => 0; sub f { $a[Z] = 5; $_[0] } print f($a[0]), "\n";
