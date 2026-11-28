my $o = {k=>1}; my $p = $o; sub c { $o->{k} = 9; 0 } my $s = $p->{k} . c(); print "$s\n";
