my @a=(1,2); sub f { $_[0] = 9 } my $s = $a[0]; f($a[0]); print "$s $a[0]\n";
