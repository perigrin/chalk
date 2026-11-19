our @q; sub add { push @q, $_[0] } for my $i (1..3) { add($i); my $n = @q; print $n } print "\n";
