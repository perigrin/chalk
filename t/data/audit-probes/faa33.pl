my @a=(1); sub f { push @a,2; $_[0] } print f($a[0]),"\n";
