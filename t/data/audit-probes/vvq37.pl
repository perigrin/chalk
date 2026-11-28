my $o = {k=>1}; my $r = \$o->{k}; sub c { $o->{k} = 9; 0 } my @l = ($$r, c()); print "@l\n";
