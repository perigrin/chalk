my @a=(1); my $f = sub { $a[0]=7; 0 }; my $n = ($a[0] = 5) + $f->(); print "$n\n";
