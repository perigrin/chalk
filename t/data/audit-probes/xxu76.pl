our @x = (1); sub c { push @x, 3; 2 } my $s = @x . c(); my $t = scalar(@x) + c(); print "$s$t\n";
