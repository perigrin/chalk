my (@a,@b); for my $c (0,1,1) { push @{ $c ? \@a : \@b }, $c } print scalar(@a), scalar(@b), "\n";
