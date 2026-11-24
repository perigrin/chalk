my @a=(1); sub f { $a[0]=2; $_[0] } print f($a[0]),"\n";
