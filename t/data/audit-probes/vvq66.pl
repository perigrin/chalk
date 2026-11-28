my $a = [1,2]; my $b = [5]; my @l = (@$a, @$b); push @$a, 3; print "@l\n";
