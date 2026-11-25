my @a=(1); my $s = ($a[0] = "a") . ($a[0] = "b"); print "$s\n";
