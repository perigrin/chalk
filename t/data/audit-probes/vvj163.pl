my @a = (1,2,3); sub ret { return @a[0,1] } my @b = ret(); my $l = ret(); print "@b$l\n";
