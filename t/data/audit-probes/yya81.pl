my @a=(1,2,3); sub f { my $p=shift; $a[1]=9; my $q=shift; "$p$q" } print f(@a), "\n";
