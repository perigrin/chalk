my @a=(1,2); sub f { my $s="@_"; $a[0]=9; $s } print f(@a), "\n";
