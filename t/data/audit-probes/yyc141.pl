my @a=(1,2,3); my $c=1; my @b=(@a, $c ? ($a[0]=9) : 0); print "@b\n";
