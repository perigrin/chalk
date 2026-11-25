my @a=(1,2,3); my $f = sub { $a[0]=9; 0 }; my @b=(@a, $f->()); print "@b\n";
