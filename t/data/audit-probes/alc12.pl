my @a=(1,2); sub f { shift @a; $_[0] } print f($a[1]),"\n";
