my $s = "x=1,y=22,z=333"; my @p = map { [split /=/] } split /,/, $s; my $sum = 0; $sum += $_->[1] for @p; (my $k = join "", map { $_->[0] } @p) =~ tr/a-z/A-Z/; print "$sum$k\n";
