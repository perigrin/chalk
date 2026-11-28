my @st; sub walk { my ($t) = @_; return unless $t; walk($t->[0]); push @st, $t->[1]; walk($t->[2]) } walk([[undef, 1, undef], 2, [undef, 3, undef]]); print "@st\n";
