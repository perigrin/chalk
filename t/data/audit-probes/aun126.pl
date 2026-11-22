my @a = (1,2); my $r = \@a; my $c = @a; @$r = (); my $d = @a; print "$c $d\n";
