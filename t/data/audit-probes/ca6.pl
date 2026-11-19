my @log; sub t { push @log, $_[0]; $_[0] } my $r = t(1) || t(2); my $q = t(0) || t(3); print "@log $r $q\n";
