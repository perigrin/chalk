my $h={a=>1}; my %c=%$h; delete $h->{a}; print join(",", %c), "\n";
