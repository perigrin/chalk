my %h = (a => 1); my $r = \%h; my $e = exists $h{a} ? 1 : 0; delete $r->{a}; my $f = exists $h{a} ? 1 : 0; print "$e $f\n";
