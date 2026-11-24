my @a=(1,2,3); my $s=0; $s+=$_ for @a; my $i=@a; $s+=pop @a while @a; print "$s $i\n";
