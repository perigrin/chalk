my @a; $a[1][2]=5; print scalar(@a), scalar(@{$a[1]}), defined $a[0]?1:0,"\n";
