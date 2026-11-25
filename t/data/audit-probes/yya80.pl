my @a=(1,2,3); sub f { my $p=shift; $a[1]=9; my @r=@_; "$p@r" } print f(@a), "\n";
