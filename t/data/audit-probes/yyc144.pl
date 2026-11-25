my @a=(1,2,3); my $r=\@a; my @b=(@$r, $a[0]=9); print "@b\n";
