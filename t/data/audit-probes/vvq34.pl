my %h = (k=>1); my $r = \%h; sub c { $h{k} = 9; 0 } my @l = ($r->{k}, c()); print "@l\n";
