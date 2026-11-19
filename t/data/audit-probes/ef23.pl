my @a = (1,2); my $r = \@a; my $n = @$r; push @a, 3; my $m = @$r; print "$n$m\n";
