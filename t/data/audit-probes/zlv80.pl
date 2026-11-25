my $x=1; local $_ = ($x += 4); $_++; print "$x $_\n";
