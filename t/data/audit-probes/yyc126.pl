my @a=(1); my $e=\$a[0]; my @l = ($a[0], $$e = 7); print "@l\n";
