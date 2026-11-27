my @a = ("ab"); my $n = ($a[0] =~ tr/a/x/); my $t = $a[0] =~ tr/x/y/r; print "$n$t@a\n";
