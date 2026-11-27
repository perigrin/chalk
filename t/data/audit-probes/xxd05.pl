my @a=(1,2); my $r=\@a; my @l = ($a[0], push(@$r, 3), scalar(@a)); print "@l\n";
