my @a=(1,2,3); sub f { my $p=shift; my @r=@_; $a[1]=9; "$p@r" } print f(@a), "\n";
