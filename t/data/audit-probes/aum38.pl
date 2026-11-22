my $o = {v=>1}; my $y = 2; ($o->{v}, $y) = ($y, $o->{v}); print "$o->{v} $y\n";
