my $r = [1,2,3]; my ($x, @rest) = @$r; @$r = (); print "$x@rest\n";
