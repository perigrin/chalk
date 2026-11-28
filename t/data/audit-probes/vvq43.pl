my $o = [1]; sub c { push @$o, 9; 0 } my @l = (@$o, c()); print "@l\n";
