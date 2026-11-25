my @a=(1,2); my $e=\$a[0]; my @b = (@a, $$e = 7); print "@b\n";
