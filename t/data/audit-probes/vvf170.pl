my $r = {k=>1}; sub c { $r->{k} = 9; 0 } my @l = ($r->{k}, c()); print "@l\n";
