my @a = (1,2,3); my ($f, $l) = @a[0,-1]; my @m = @a[1..$#a]; print "$f$l@m\n";
