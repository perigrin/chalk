my (@a,@b); my $c=1; push @{ $c ? \@a : \@b }, 1; print scalar(@a), scalar(@b), "\n";
