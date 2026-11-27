our $x = 1; sub c { $x = 3; 2 } my $r = {a => $x, b => c()}; print "$r->{a}$r->{b}\n";
