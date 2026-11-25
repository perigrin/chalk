my @a=(1,2,3); my $r=\@a; my @b=(@a, $r->[0]=9); print "@b\n";
