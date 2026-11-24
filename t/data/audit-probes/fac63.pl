my @a=(1,2); my ($r1,$r2)=(\@a,[@a]); push @$r1,3; print scalar(@$r2), scalar(@a), "\n";
