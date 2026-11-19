our @q = (1,2,3); sub take { shift @q } my $n = @q; take(); my $m = @q; print "$n$m\n";
