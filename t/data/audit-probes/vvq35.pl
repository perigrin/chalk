my %h = (k=>1); my $r = \$h{k}; sub c { $h{k} = 9; 0 } my @l = ($$r, c()); print "@l\n";
