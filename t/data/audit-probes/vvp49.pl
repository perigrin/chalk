my @a = (1,2); sub f { $a[-2] = 5; return $_[0] } my $v = f($a[0]); print "$v\n";
