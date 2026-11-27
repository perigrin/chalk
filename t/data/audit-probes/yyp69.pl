my @a=(1,2); sub inc { $_[0]++ } sub f { unshift @a, 0; inc($_[0]); "@a" } print f($a[0]), "\n";
