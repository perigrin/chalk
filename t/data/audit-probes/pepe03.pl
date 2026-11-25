my @a=(1); my $r=\$a[0]; my $n = $a[0] + ($$r = 3); print "$n\n";
