my $a = [1,2]; my $h = {c=>3}; my @l = (%$h, @$a); push @$a, 3; print "@l\n";
