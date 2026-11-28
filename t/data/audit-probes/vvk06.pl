sub f { $_[0] = "n" } my $r = {}; f($r->{k}); print join(",", %$r), "\n";
