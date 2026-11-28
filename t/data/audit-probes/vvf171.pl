my $r = {k=>1}; sub c { $r->{k} = 9; 0 } my $s = $r->{k} . c(); print "$s\n";
