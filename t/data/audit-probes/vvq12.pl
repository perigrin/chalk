my $v = 1; my $r = \$v; sub c { $v = 9; 0 } my ($p, $q) = ($$r, c()); print "$p$q\n";
