my @a=(1,2); sub f { unshift @a, 0; $_[0] } print f($a[0]), "\n";
