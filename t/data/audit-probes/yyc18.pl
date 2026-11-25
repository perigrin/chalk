my (@a,@b); my $c=0; ($c ? @a : @b) = (1,2); print scalar(@a), scalar(@b), "\n";
