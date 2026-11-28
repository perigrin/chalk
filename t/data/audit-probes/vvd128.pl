sub as { my @a = (1,2,3); return @a[0,1] = (7,8) } my $s = as(); my @l = as(); print "$s|@l\n";
